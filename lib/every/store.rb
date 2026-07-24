module Every
  # Task registry: one JSON file. Run history: one JSONL file per task.
  class Store
    FILE = File.join(DATA_DIR, "tasks.json")

    def self.load
      data = File.exist?(FILE) ? JSON.parse(File.read(FILE)) : {}
      new(data)
    rescue JSON::ParserError => e
      abort "every: #{FILE} is corrupted (#{e.message}) — fix or delete it"
    end

    def initialize(data)
      @data = data
      @data["tasks"] ||= {}
    end

    def tasks
      @data["tasks"]
    end

    def [](name)
      tasks[name]
    end

    def add(name, attrs)
      tasks[name] = attrs
      save
    end

    def update(name, attrs)
      tasks[name] = (tasks[name] || {}).merge(attrs)
      save
    end

    def remove(name)
      tasks.delete(name)
      save
    end

    def last_run(name)
      path = File.join(RUNS_DIR, "#{name}.jsonl")
      return nil unless File.exist?(path)
      line = nil
      File.foreach(path) { |l| line = l unless l.strip.empty? }
      line && JSON.parse(line)
    rescue JSON::ParserError
      nil
    end

    private

    # Atomic write: a crash mid-write must never truncate the task registry.
    # Write a temp file, fsync, then rename over the target (atomic on the same
    # filesystem).
    def save
      FileUtils.mkdir_p(DATA_DIR)
      tmp = "#{FILE}.tmp.#{Process.pid}"
      File.open(tmp, "w") do |f|
        f.write(JSON.pretty_generate(@data) + "\n")
        f.flush
        f.fsync
      end
      File.rename(tmp, FILE)
    ensure
      File.delete(tmp) if tmp && File.exist?(tmp)
    end
  end
end
