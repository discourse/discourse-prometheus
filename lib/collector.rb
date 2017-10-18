# frozen_string_literal: true

class DiscoursePrometheus::Collector

  def self.instance
    @instance
  end

  def start(*args)
    raise "start can only be called once" if @instance
    @instance = self.new(*args)
    @instance.start
  end

  def initialize(log_reader, reader, writer)
    @log_reader = log_reader
    @reader = reader
    @writer = writer
  end

  def metrics
    @writer.puts "metrics"
    parse_metrics(@metrics_reader.gets)
  end

  def parse_metrics(str)
  end

  def log_report(str)
    parse_metrics(str)
  end

  def handle_command(str)
  end

  def start
    @logger_thread = Thread.new do
      while true
        log_report(@log_reader.gets)
      end
    end

    @manager_thread = Thread.new do
      while true
        handle_command(@reader.gets)
      end
    end
  end
end
