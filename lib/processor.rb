# frozen_string_literal: true

class ::DiscoursePrometheus::Processor

  # returns an array of Prometheus metrics
  def self.process(metrics)
    processor = new

    begin
      while true
        metric = metrics.next
        if String === metric
          metric = DiscoursePrometheus::Metric.parse(metric)
        end
        processor.process metric
      end
    rescue StopIteration
    end

    processor.prometheus_metrics
  end

  def initialize
    @page_views = DiscoursePrometheus::Counter.new("page_views", "Page views reported by admin dashboard")
    @http_requests = DiscoursePrometheus::Counter.new("http_requests", "Total HTTP requests from web app")

    @http_duration_seconds = DiscoursePrometheus::Summary.new("http_duration_seconds", "Time spent in HTTP reqs in seconds")
    @http_redis_duration_seconds = DiscoursePrometheus::Summary.new("http_redis_duration_seconds", "Time spent in HTTP reqs in redis seconds")
    @http_sql_duration_seconds = DiscoursePrometheus::Summary.new("http_sql_duration_seconds", "Time spent in HTTP reqs in SQL in seconds")
  end

  def process(metric)
    # STDERR.puts metric.to_h.inspect
    # STDERR.puts metric.controller.to_s + " " + metric.action.to_s

    labels =
      if observe_timings?(metric)
        { controller: metric.controller, action: metric.action }
      else
        { controller: 'other', action: 'other' }
      end

    @http_duration_seconds.observe(metric.duration, labels)
    @http_sql_duration_seconds.observe(metric.sql_duration, labels)
    @http_redis_duration_seconds.observe(metric.redis_duration, labels)

    db = metric.db.presence || "default"

    if metric.tracked
      hash = { db: db }

      if metric.crawler
        hash[:type] = "crawler"
        hash[:device] = "crawler"
      else
        hash[:type] = metric.logged_in ? "logged_in" : "anon"
        hash[:device] = metric.mobile ? "mobile" : "desktop"
      end
      @page_views.observe(hash)
    end

    hash = { db: db }
    if metric.background && metric.status_code < 500
      hash[:type] = "background"
      hash[:status] = "-1"
    else
      hash[:type] = "regular"
      hash[:status] = metric.status_code
    end
    @http_requests.observe(hash)
  end

  def prometheus_metrics
    [@page_views, @http_requests, @http_duration_seconds,
     @http_redis_duration_seconds, @http_sql_duration_seconds]
  end

  private

  def observe_timings?(metric)
    (metric.controller == "list" && metric.action == "latest") ||
    (metric.controller == "list" && metric.action == "top") ||
    (metric.controller == "topics" && metric.action == "show") ||
    (metric.controller == "users" && metric.action == "show") ||
    (metric.controller == "categories" && metric.action == "categories_and_latest")
  end
end
