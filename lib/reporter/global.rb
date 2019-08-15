# frozen_string_literal: true

module DiscoursePrometheus::Reporter
  class Global
    def self.clear_connections!
      ActiveRecord::Base.connection_handler.clear_active_connections!
    rescue => e
      begin
        Discourse.warn_exception(e, message: "Failed to clear active connections")
      rescue => e1
        # never crash this thread
        STDERR.puts "ERR failed to log warning: #{e1}"
      end
    end

    def self.start(client)
      global_collector = new
      Thread.new do
        clear_connections!
        while true
          begin
            metric = global_collector.collect
            client.send_json metric
          rescue => e
            Discourse.warn_exception(e, message: "Prometheus Discourse Failed To Collect Global Stats")
          ensure
            clear_connections!
            sleep 5
          end
        end
      end

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
