module Every
  # Parses human schedule tokens into launchd-compatible triggers.
  #
  #   15m / 2h / 90s            -> StartInterval (seconds)
  #   hourly                    -> StartInterval 3600
  #   day 9am                   -> daily at 9:00
  #   day 9am,6pm               -> daily at 9:00 and 18:00
  #   weekdays 9:30             -> Mon-Fri at 9:30
  #   weekends 11am             -> Sat+Sun at 11:00
  #   monday 10:00              -> weekly
  #   monday,thursday 10:00     -> twice a week
  #
  # Calendar schedules normalize to a list of {weekday?, hour, minute}
  # entries — one launchd StartCalendarInterval dict each.
  class Schedule
    WEEKDAYS = {
      "sunday" => 0, "monday" => 1, "tuesday" => 2, "wednesday" => 3,
      "thursday" => 4, "friday" => 5, "saturday" => 6
    }.freeze

    DAY_SETS = {
      "day" => [nil],
      "daily" => [nil],
      "weekdays" => [1, 2, 3, 4, 5],
      "weekends" => [0, 6]
    }.freeze

    UNIT_SECONDS = { "s" => 1, "m" => 60, "h" => 3600 }.freeze
    MIN_INTERVAL = 10

    attr_reader :raw, :kind, :interval, :entries

    def self.parse(tokens)
      raw = tokens.join(" ")
      raise ArgumentError, "empty schedule" if tokens.empty?

      first = tokens[0].to_s.downcase

      if tokens.length == 1 && first =~ /\A(\d+)(s|m|h)\z/
        secs = Regexp.last_match(1).to_i * UNIT_SECONDS[Regexp.last_match(2)]
        if secs < MIN_INTERVAL
          raise ArgumentError, "interval too small (min #{MIN_INTERVAL}s)"
        end
        new(raw, :interval, interval: secs)
      elsif tokens.length == 1 && first == "hourly"
        new(raw, :interval, interval: 3600)
      elsif tokens.length == 2
        days = parse_days(first)
        times = parse_times(tokens[1])
        entries = days.product(times).map do |wd, (h, m)|
          e = { "hour" => h, "minute" => m }
          e["weekday"] = wd if wd
          e
        end.uniq
        new(raw, :calendar, entries: entries)
      else
        raise ArgumentError,
              "cannot parse schedule #{raw.inspect} " \
              "(examples: 15m | hourly | day 9am,6pm | weekdays 9:30 | monday,thursday 10:00)"
      end
    end

    def self.parse_days(spec)
      return DAY_SETS[spec] if DAY_SETS.key?(spec)

      parts = spec.split(",")
      unless !parts.empty? && parts.all? { |p| WEEKDAYS.key?(p) }
        raise ArgumentError,
              "cannot parse days #{spec.inspect} " \
              "(day | weekdays | weekends | monday | monday,thursday)"
      end
      parts.map { |p| WEEKDAYS[p] }.uniq
    end

    # Split a comma time list, rejecting empty segments (",", "9am,", "9am,,6pm").
    def self.parse_times(spec)
      parts = spec.to_s.split(",", -1)
      if parts.empty? || parts.any?(&:empty?)
        raise ArgumentError, "cannot parse time #{spec.inspect} (e.g. 9am or 9am,6pm)"
      end
      parts.map { |t| parse_time(t) }.uniq
    end

    def self.parse_time(str)
      m = str.to_s.downcase.match(/\A(\d{1,2})(?::(\d{2}))?(am|pm)?\z/)
      raise ArgumentError, "cannot parse time #{str.inspect}" unless m

      hour = m[1].to_i
      minute = (m[2] || "0").to_i
      ampm = m[3]
      if ampm && (hour < 1 || hour > 12)
        raise ArgumentError, "hour out of range for am/pm: #{str.inspect}"
      end
      hour += 12 if ampm == "pm" && hour < 12
      hour = 0 if ampm == "am" && hour == 12
      if hour > 23 || minute > 59
        raise ArgumentError, "time out of range: #{str.inspect}"
      end
      [hour, minute]
    end

    def initialize(raw, kind, opts = {})
      @raw = raw
      @kind = kind
      @interval = opts[:interval]
      @entries = opts[:entries]
    end

    def to_h
      h = { "raw" => raw, "kind" => kind.to_s }
      h["interval"] = interval if interval
      h["entries"] = entries if entries
      h
    end

    # Accepts current format plus the pre-0.2 "daily"/"weekly" task records.
    # Clamp any persisted weekday into 0-6 (a legacy 7 = Sunday = 0).
    def self.normalize_entries(entries)
      (entries || []).map do |e|
        e = e.dup
        e["weekday"] = e["weekday"].to_i % 7 if e["weekday"]
        e
      end
    end

    def self.from_h(h)
      case h["kind"]
      when "interval"
        new(h["raw"], :interval, interval: h["interval"])
      when "calendar"
        new(h["raw"], :calendar, entries: normalize_entries(h["entries"]))
      when "daily"
        new(h["raw"], :calendar,
            entries: [{ "hour" => h["hour"], "minute" => h["minute"] }])
      when "weekly"
        new(h["raw"], :calendar,
            entries: [{ "hour" => h["hour"], "minute" => h["minute"],
                        "weekday" => h["weekday"].to_i % 7 }])
      else
        raise ArgumentError, "unknown schedule kind #{h['kind'].inspect}"
      end
    end

    # Earliest next calendar occurrence; nil for interval schedules.
    def next_run(from = Time.now)
      return nil if kind == :interval
      entries.map { |e| next_for_entry(e, from) }.min
    end

    def next_for_entry(e, from)
      t = Time.new(from.year, from.month, from.day, e["hour"], e["minute"], 0)
      if e["weekday"]
        t = shift_days(t, (e["weekday"] - from.wday) % 7)
        t = shift_days(t, 7) if t <= from
      elsif t <= from
        t = shift_days(t, 1)
      end
      t
    end

    # Add whole calendar days keeping wall-clock hour:minute — DST-safe, unlike
    # adding N*86400 seconds (which drifts the displayed hour across a DST edge).
    def shift_days(t, days)
      return t if days.zero?
      d = Date.new(t.year, t.month, t.day) + days
      Time.new(d.year, d.month, d.day, t.hour, t.min, 0)
    end

    def human_interval
      return nil unless interval
      if interval % 3600 == 0
        "#{interval / 3600}h"
      elsif interval % 60 == 0
        "#{interval / 60}m"
      else
        "#{interval}s"
      end
    end
  end
end
