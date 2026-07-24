module Every
  # Parses human schedule tokens into a launchd-compatible trigger.
  #
  #   15m / 2h / 90s      -> StartInterval (seconds)
  #   hourly              -> StartInterval 3600
  #   day 9am / day 17:30 -> StartCalendarInterval (daily)
  #   monday 10:00        -> StartCalendarInterval (weekly)
  class Schedule
    WEEKDAYS = {
      "sunday" => 0, "monday" => 1, "tuesday" => 2, "wednesday" => 3,
      "thursday" => 4, "friday" => 5, "saturday" => 6
    }.freeze

    UNIT_SECONDS = { "s" => 1, "m" => 60, "h" => 3600 }.freeze
    MIN_INTERVAL = 10

    attr_reader :raw, :kind, :interval, :hour, :minute, :weekday

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
      elsif first == "day" && tokens.length == 2
        h, m = parse_time(tokens[1])
        new(raw, :daily, hour: h, minute: m)
      elsif WEEKDAYS.key?(first) && tokens.length == 2
        h, m = parse_time(tokens[1])
        new(raw, :weekly, hour: h, minute: m, weekday: WEEKDAYS[first])
      else
        raise ArgumentError,
              "cannot parse schedule #{raw.inspect} " \
              "(examples: 15m | hourly | day 9am | monday 10:00)"
      end
    end

    def self.parse_time(str)
      m = str.to_s.downcase.match(/\A(\d{1,2})(?::(\d{2}))?(am|pm)?\z/)
      raise ArgumentError, "cannot parse time #{str.inspect}" unless m

      hour = m[1].to_i
      minute = (m[2] || "0").to_i
      hour += 12 if m[3] == "pm" && hour < 12
      hour = 0 if m[3] == "am" && hour == 12
      if hour > 23 || minute > 59
        raise ArgumentError, "time out of range: #{str.inspect}"
      end
      [hour, minute]
    end

    def initialize(raw, kind, opts = {})
      @raw = raw
      @kind = kind
      @interval = opts[:interval]
      @hour = opts[:hour]
      @minute = opts[:minute]
      @weekday = opts[:weekday]
    end

    def to_h
      h = { "raw" => raw, "kind" => kind.to_s }
      h["interval"] = interval if interval
      h["hour"] = hour if hour
      h["minute"] = minute if minute
      h["weekday"] = weekday if weekday
      h
    end

    def self.from_h(h)
      new(h["raw"], h["kind"].to_sym,
          interval: h["interval"], hour: h["hour"],
          minute: h["minute"], weekday: h["weekday"])
    end

    # Next calendar occurrence; nil for interval schedules.
    def next_run(from = Time.now)
      case kind
      when :daily
        t = Time.new(from.year, from.month, from.day, hour, minute, 0)
        t += 86_400 if t <= from
        t
      when :weekly
        t = Time.new(from.year, from.month, from.day, hour, minute, 0)
        t += ((weekday - from.wday) % 7) * 86_400
        t += 7 * 86_400 if t <= from
        t
      end
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
