module DiscoursePrometheus
  class Collector

    def initialize
      @pipe = BigPipe.new(0, reporter: self, processor: self)
      @processor = Processor.new
      @mutex = Mutex.new
    end

    def stop
      @pipe.destroy!
      @pipe = nil
    end

    def <<(metric)
      @pipe << metric
    end

    def flush
      @pipe.flush
    end

    def prometheus_metrics_text
      report.join("\n")
    end

    def process(metric)
      @mutex.synchronize do
        @processor.process(metric)
      end
      nil
    end

    def report(messages = nil)
      lines = []
      @mutex.synchronize do
        @processor.prometheus_metrics.each do |metric|
          lines += metric.to_prometheus_text.split("\n")
          lines << "\n"
        end
      end
      lines
    end
  end
end
