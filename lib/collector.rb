# frozen_string_literal: true

module ::DiscoursePrometheus
  class Collector < ::PrometheusExporter::Server::CollectorBase
    MAX_PROCESS_METRIC_AGE = 60

    # convenience shortcuts
    Gauge = ::PrometheusExporter::Metric::Gauge
    Counter = ::PrometheusExporter::Metric::Counter
    Summary = ::PrometheusExporter::Metric::Summary

    def initialize
      @page_views = nil
      @http_requests = nil
      @http_duration_seconds = nil
      @http_redis_duration_seconds = nil
      @http_sql_duration_seconds = nil
      @http_net_duration_seconds = nil
      @http_queue_duration_seconds = nil
      @http_forced_anon_count = nil

      @scheduled_job_duration_seconds = nil
      @scheduled_job_count = nil
      @sidekiq_job_duration_seconds = nil
      @sidekiq_job_count = nil

      @missing_s3_uploads = nil

      @process_metrics = []
      @global_metrics = []

      @custom_metrics = nil
    end

    def process(str)
      obj = Oj.load(str, mode: :object)
      metric = DiscoursePrometheus::InternalMetric::Base.from_h(obj)

      if InternalMetric::Process === metric
        process_process(metric)
      elsif InternalMetric::Web === metric
        process_web(metric)
      elsif InternalMetric::Job === metric
        process_job(metric)
      elsif InternalMetric::Global === metric
        process_global(metric)
      elsif InternalMetric::Custom === metric
        process_custom(metric)
      end
    end

    def prometheus_metrics_text
      prometheus_metrics.map(&:to_prometheus_text).join("\n")
    end

    def process_custom(metric)
      obj = ensure_custom_metric(metric)
      if Counter === obj
        obj.observe(metric.value || 1, metric.labels)
      elsif Gauge === obj
        obj.observe(metric.value, metric.labels)
      end
    end

    def ensure_custom_metric(metric)
      @custom_metrics ||= {}
      if !(obj = @custom_metrics[metric.name])
        if metric.type == "Counter"
          obj = Counter.new(metric.name, metric.description)
        elsif metric.type == "Gauge"
          obj = Gauge.new(metric.name, metric.description)
        else
          raise ApplicationError, "Unknown metric type #{metric.type}"
        end
        @custom_metrics[metric.name] = obj
      end

      obj
    end

    def process_global(metric)
      ensure_global_metrics
      @global_metrics.each do |gauge|
        values = metric.send(gauge.name)
        # global metrics "reset" each time they are called
        # this will delete labels we don't need anymore
        gauge.reset!

        if values.is_a?(Hash)
          values.each do |labels, value|
            gauge.observe(value, labels)
          end
        else
          gauge.observe(values)
        end
      end
    end

    def ensure_global_metrics
      return if @global_metrics.length > 0

      global_metrics = []

      global_metrics << Gauge.new(
        "postgres_readonly_mode",
        "Indicates whether site is in readonly mode due to PostgreSQL failover"
      )

      global_metrics << Gauge.new(
        "redis_master_available",
        "Whether or not we have an active connection to the master Redis",
      )

      global_metrics << Gauge.new(
        "redis_slave_available",
        "Whether or not we have an active connection a Redis slave"
      )

      global_metrics << Gauge.new(
        "postgres_master_available",
        "Whether or not we have an active connection to the master PostgreSQL"
      )

      global_metrics << Gauge.new(
        "postgres_replica_available",
        "Whether or not we have an active connection to the replica PostgreSQL"
      )

      global_metrics << Gauge.new(
        "active_app_reqs",
        "Number of active web requests in progress"
      )

      global_metrics << Gauge.new(
        "queued_app_reqs",
        "Number of queued web requests"
      )

      global_metrics << Gauge.new(
        "sidekiq_jobs_enqueued",
        "Number of jobs queued in the Sidekiq worker processes"
      )

      global_metrics << Gauge.new(
        "sidekiq_processes",
        "Number of Sidekiq job processes"
      )

      global_metrics << Gauge.new(
        "sidekiq_paused",
        "Whether or not Sidekiq is paused"
      )

      global_metrics << Gauge.new(
        "sidekiq_workers",
        "Total number of active sidekiq workers"
      )

      global_metrics << Gauge.new(
        "sidekiq_jobs_stuck",
        "Number of sidekiq jobs which have been running for more than #{InternalMetric::Global::STUCK_SIDEKIQ_JOB_MINUTES} minutes"
      )

      global_metrics << Gauge.new(
        "scheduled_jobs_stuck",
        "Number of scheduled jobs which have been running for more than their expected duration"
      )

      global_metrics << Gauge.new(
        "missing_s3_uploads",
        "Number of missing uploads in S3"
      )

      global_metrics << Gauge.new(
        "version_info",
        "Labelled with `revision` (current core commit hash), and `version` (Discourse::VERSION::STRING)"
      )

      global_metrics << Gauge.new(
        "readonly_sites",
        "Count of sites currently in readonly mode, grouped by the relevant key from Discourse::READONLY_KEYS"
      )

      @global_metrics = global_metrics
    end

    def process_job(metric)
      ensure_job_metrics
      hash = {
        job_name: metric.job_name
      }
      if metric.scheduled
        @scheduled_job_duration_seconds.observe(metric.duration, hash)
        @scheduled_job_count.observe(1, hash)
      else
        @sidekiq_job_duration_seconds.observe(metric.duration, hash)
        @sidekiq_job_count.observe(1, hash)
      end
    end

    def ensure_job_metrics
      unless @scheduled_job_count
        @scheduled_job_duration_seconds = Counter.new("scheduled_job_duration_seconds", "Total time spent in scheduled jobs")
        @scheduled_job_count = Counter.new("scheduled_job_count", "Total number of scheduled jobs executued")
        @sidekiq_job_duration_seconds = Counter.new("sidekiq_job_duration_seconds", "Total time spent in sidekiq jobs")
        @sidekiq_job_count = Counter.new("sidekiq_job_count", "Total number of sidekiq jobs executed")
      end
    end

    def process_process(metric)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # process clock monotonic is used here so keep collector process time
      metric.created_at = now
      @process_metrics.delete_if do |current|
        metric.pid == current.pid || (current.created_at + MAX_PROCESS_METRIC_AGE < now)
      end
      @process_metrics << metric
    end

    def ensure_web_metrics
      unless @page_views
        @page_views = Counter.new("page_views", "Page views reported by admin dashboard")
        @http_requests = Counter.new("http_requests", "Total HTTP requests from web app")
        @http_forced_anon_count = Counter.new("http_forced_anon_count", "Total count of logged in requests forced into anonymous mode")

        @http_duration_seconds = Summary.new("http_duration_seconds", "Time spent in HTTP reqs in seconds")
        @http_redis_duration_seconds = Summary.new("http_redis_duration_seconds", "Time spent in HTTP reqs in redis seconds")
        @http_sql_duration_seconds = Summary.new("http_sql_duration_seconds", "Time spent in HTTP reqs in SQL in seconds")
        @http_net_duration_seconds = Summary.new("http_net_duration_seconds", "Time spent in external network requests")
        @http_queue_duration_seconds = Summary.new("http_queue_duration_seconds", "Time spent queueing requests between NGINX and Ruby")

        @http_sql_calls_per_request = Gauge.new("http_sql_calls_per_request", "How many SQL statements ran per request")

        @http_anon_cache_store = Counter.new("http_anon_cache_store", "How many a payload is stored in redis for anonymous cache")
        @http_anon_cache_hit = Counter.new("http_anon_cache_hit", "How many a payload from redis is used for anonymous cache")
      end
    end

    def process_web(metric)
      ensure_web_metrics
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
      @http_net_duration_seconds.observe(metric.net_duration, labels)
      @http_queue_duration_seconds.observe(metric.queue_duration, labels)
      @http_sql_calls_per_request.observe(metric.sql_calls, labels.merge(logged_in: metric.logged_in))

      if cache = metric.cache
        if cache == "store"
          @http_anon_cache_store.observe(1, labels)
        elsif cache == "true"
          @http_anon_cache_hit.observe(1, labels)
        end
      end

      db = metric.db || "default"

      if metric.tracked
        hash = { db: db }

        if metric.crawler
          hash[:type] = "crawler"
          hash[:device] = "crawler"
        else
          hash[:type] = metric.logged_in ? "logged_in" : "anon"
          hash[:device] = metric.mobile ? "mobile" : "desktop"
        end
        @page_views.observe(1, hash)
      end

      api_type =
        if metric.user_api
          "user"
        elsif metric.admin_api
          "admin"
        else
          "web"
        end

      hash = { db: db, api: api_type, verb: metric.verb }
      if metric.background
        hash[:type] = "background"
        # hijacked but never got the actual status, message bus
        if metric.status_code == 418
          hash[:status] = "-1"
        else
          hash[:status] = metric.status_code
        end
      else
        hash[:type] = "regular"
        hash[:status] = metric.status_code
      end

      if metric.forced_anon
        @http_forced_anon_count.observe(1, hash)
      end
      @http_requests.observe(1, hash)
    end

    def prometheus_metrics
      metrics = web_metrics + process_metrics + job_metrics + @global_metrics
      if @custom_metrics
        metrics += @custom_metrics.values
      end
      metrics
    end

    private

    def job_metrics
      if @scheduled_job_duration_seconds
        [
          @scheduled_job_duration_seconds,
          @scheduled_job_count,
          @sidekiq_job_duration_seconds,
          @sidekiq_job_count,
        ]
      else
        []
      end

    end

    def process_metrics
      # this are only calculated when we ask for them on the fly
      return [] if @process_metrics.length == 0
      metrics = []
      InternalMetric::Process::GAUGES.each do |key, name|
        gauge = Gauge.new(key.to_s, name)
        metrics << gauge
        @process_metrics.each do |metric|
          values = metric.send(key)
          default_labels = { type: metric.type, pid: metric.pid }

          if values.is_a?(Hash)
            values.each do |labels, value|
              gauge.observe(value, default_labels.merge(labels))
            end
          else
            gauge.observe(values, default_labels)
          end
        end
      end
      InternalMetric::Process::COUNTERS.each do |key, name|
        counter = Counter.new(key.to_s, name)
        metrics << counter
        @process_metrics.each do |metric|
          counter.observe(metric.send(key), type: metric.type, pid: metric.pid)
        end
      end
      metrics
    end

    def web_metrics
      if @page_views
        [@page_views, @http_requests, @http_duration_seconds,
          @http_redis_duration_seconds, @http_sql_duration_seconds,
          @http_net_duration_seconds, @http_queue_duration_seconds,
          @http_forced_anon_count, @http_sql_calls_per_request,
          @http_anon_cache_store, @http_anon_cache_hit
        ]
      else
        []
      end
    end

    def observe_timings?(metric)
      (metric.controller == "list" && metric.action == "latest") ||
      (metric.controller == "list" && metric.action == "top") ||
      (metric.controller == "topics" && metric.action == "show") ||
      (metric.controller == "users" && metric.action == "show") ||
      (metric.controller == "categories" && metric.action == "categories_and_latest")
    end
  end
end
