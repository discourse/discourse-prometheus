class ::DiscoursePrometheus::Processor

  # returns an array of Prometheus metrics
  def self.process(metrics)
    processor = new

    begin
      while true
        processor.process metrics.next
      end
    rescue StopIteration
    end

    processor.prometheus_metrics
  end

  def initialize
    @page_views = DiscoursePrometheus::Counter.new("page_views", "Page views reported by admin dashboard")
    @http_requests = DiscoursePrometheus::Counter.new("http_requests", "Total HTTP requests from web app")
  end

  def process(metric)
    if metric.tracked
      hash = { host: metric.host }
      if metric.crawler
        hash[:type] = "crawler"
      else
        hash[:type] = metric.logged_in ? "logged_in" : "anon"
        hash[:device] = metric.mobile ? "mobile" : "desktop"
      end
      @page_views.observe(hash)
    end

    hash = { host: metric.host }
    if metric.background && metric.status_code < 500
      hash[:type] = "background"
    else
      hash[:status] = metric.status_code
    end
    @http_requests.observe(hash)
  end

  def prometheus_metrics
    [@page_views, @http_requests]
  end
end
