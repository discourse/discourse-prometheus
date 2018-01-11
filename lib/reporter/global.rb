module DiscoursePrometheus::Reporter
  class Global

    def self.start(client)
      global_collector = new
      Thread.new do
        while true
          begin
            metric = global_collector.collect
            client.send metric
          rescue => e
            Rails.logger.warn("Prometheus Discoruse Failed To Collect Global Stats #{e}")
          ensure
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
