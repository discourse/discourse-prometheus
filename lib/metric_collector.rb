module DiscoursePrometheus
  class MetricCollector

    def initialize
      @pipe = BigPipe.new(0, reporter: self, processor: self)
      @processor = Processor.new
    end

    def <<(metric)
      @pipe << metric
    end

    def prometheus_metrics_text
      # cause we want UTF-8 not ASCII
      text = "".dup
      @pipe.process do |line|
        text << line
        text << "\n"
      end
      text
    end

    def process(metric)
      @processor.process(metric)
      nil
    end

    def report(messages)
      lines = []
      @processor.prometheus_metrics.each do |metric|
        lines += metric.to_prometheus_text.split("\n")
        lines << "\n"
      end
      lines
    end
  end
end
