# frozen_string_literal: true

module ::DiscoursePrometheus
  class Processor
    MAX_PROCESS_METRIC_AGE = 60

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
      @page_views = Counter.new("page_views", "Page views reported by admin dashboard")
      @http_requests = Counter.new("http_requests", "Total HTTP requests from web app")

      @http_duration_seconds = Summary.new("http_duration_seconds", "Time spent in HTTP reqs in seconds")
      @http_redis_duration_seconds = Summary.new("http_redis_duration_seconds", "Time spent in HTTP reqs in redis seconds")
      @http_sql_duration_seconds = Summary.new("http_sql_duration_seconds", "Time spent in HTTP reqs in SQL in seconds")

      @process_metrics = []
    end

    def process(metric)
      if ProcessMetric === metric
        process_process(metric)
      elsif Metric === metric
        process_web(metric)
      end
    end

    def process_process(metric)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @process_metrics.delete_if do |current|
        metric.pid == current.pid || (metric.created_at + MAX_PROCESS_METRIC_AGE < now)
      end
      @process_metrics << metric
    end

    def process_web(metric)
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

    def process_metrics
      # this are only calculated when we ask for them on the fly
      return [] if @process_metrics.length == 0
      metrics = []
      ProcessMetric::GAUGES.each do |key, name|
        gauge = Gauge.new(key.to_s, name)
        metrics << gauge
        @process_metrics.each do |metric|
          gauge.observe(metric.send(key), type: metric.type, pid: metric.pid)
        end
      end
      ProcessMetric::COUNTERS.each do |key, name|
        counter = Counter.new(key.to_s, name)
        metrics << counter
        @process_metrics.each do |metric|
          counter.observe({ type: metric.type, pid: metric.pid }, metric.send(key))
        end
      end
      metrics
    end

    def prometheus_metrics
      [@page_views, @http_requests, @http_duration_seconds,
       @http_redis_duration_seconds, @http_sql_duration_seconds] + process_metrics
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
end
