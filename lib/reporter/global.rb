# frozen_string_literal: true

module DiscoursePrometheus::Reporter
  class Global

    def self.clear_connections!
      ActiveRecord::Base.connection_handler.clear_active_connections!
    end

    def self.iteration(global_collector, client)
      clear_connections!
      metric = global_collector.collect
      client.send_json metric
      clear_connections!
    rescue => e
      begin
        Discourse.warn_exception(e, message: "Prometheus Discourse Failed To Collect Global Stats")
      rescue => e1
        # never crash an iteration
        STDERR.puts "ERR failed to log warning: #{e1}" rescue nil
      end
    end

    def self.sleep_unless_interrupted(seconds)
      IO.select([@r], nil, nil, seconds)
    end

    def self.start(client)
      @r, @w = IO.pipe
      global_collector = new
      Thread.new do
        while !@stopping
          iteration(global_collector, client)
          sleep_unless_interrupted 5
        end
      end
    end

    def self.stop
      @stopping = true
      @w.close
    end

    def initialize(recycle_every: 6)
      @recycle_every = recycle_every
      @collections = 0
      @metrics = ::DiscoursePrometheus::InternalMetric::Global.new
    end

    def collect
      if @collections >= @recycle_every
        @metrics = ::DiscoursePrometheus::InternalMetric::Global.new
        @collections = 0
      else
        @collections += 1
      end

      @metrics.collect
      @metrics
    end
  end
end
