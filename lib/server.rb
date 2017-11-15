# frozen_string_literal: true

require 'webrick'
require 'raindrops'
require 'timeout'

module DiscoursePrometheus
  class Server
    def initialize(port: GlobalSetting.prometheus_collector_port, collector:)

      @server = WEBrick::HTTPServer.new(
        Port: port,
        AccessLog: []
      )

      @collector = collector
      @port = port

      @server.mount_proc '/' do |req, res|
        res['ContentType'] = 'text/plain; charset=utf-8'
        if req.path == '/metrics'
          res.status = 200
          res.body = metrics
        else
          res.status = 404
          res.body = "Not Found! The Prometheus Discourse plugin only listens on /metrics"
        end
      end
    end

    def start
      @runner ||= Thread.start do
        begin
          @server.start
        rescue => e
          STDERR.puts "Failed to start prometheus collector web on port #{@port}: #{e}"
        end
      end
    end

    def stop
      @server.shutdown
    end

    def metrics
      redis_config = GlobalSetting.redis_config

      redis_master_running = test_redis(redis_config[:host], redis_config[:port], redis_config[:password])
      redis_slave_running = 0

      if redis_config[:slave_host]
        redis_slave_running = test_redis(redis_config[:slave_host], redis_config[:slave_port], redis_config[:password])
      end

      net_stats = Raindrops::Linux::tcp_listener_stats("0.0.0.0:3000")["0.0.0.0:3000"]

      @metrics = []

      add_gauge(
        "postgres_readonly_mode",
        "Indicates whether site is in readonly mode due to PostgreSQL failover",
        primary_site_readonly?
      )

      add_gauge(
        "transient_readonly_mode",
        "Indicates whether site is in a transient readonly mode",
        recently_readonly?
      )

      add_gauge(
        "redis_master_available",
        "Whether or not we have an active connection to the master Redis",
        redis_master_running
      )

      add_gauge(
        "redis_slave_available",
        "Whether or not we have an active connection a Redis slave",
        redis_slave_running
      )

      add_gauge(
        "active_app_reqs",
        "Number of active web requests in progress",
        net_stats.active
      )

      add_gauge(
        "queued_app_reqs",
        "Number of queued web requests",
        net_stats.queued
      )

      add_gauge(
        "sidekiq_jobs_enqueued",
        "Number of jobs queued in the Sidekiq worker processes",
        Sidekiq::Stats.new.enqueued
      )

      add_gauge(
        "sidekiq_processes",
        "Number of Sidekiq job processors",
        Sidekiq::ProcessSet.new.size || 0
      )

      metric_text = nil
      begin
        Timeout::timeout(2) do
          metric_text = @collector.prometheus_metrics_text
        end
      rescue Timeout::Error
        # we timed out ... bummer
        STDERR.puts "Generating Prometheus metrics text timed out"
      end

      add_gauge(
        "collector_working",
        "Is the master process collector able to collect metrics",
        metric_text.present? ? 1 : 0
      )

      <<~TEXT
      #{@metrics.map(&:to_prometheus_text).join("\n\n")}
      #{metric_text}
      TEXT
    end

    def add_gauge(name, help, value)
      gauge = Gauge.new(name, help)
      gauge.observe(value)
      @metrics << gauge
    end

    def primary_site_readonly?
      return "1" unless defined?(Discourse::PG_READONLY_MODE_KEY)
      $redis.without_namespace.get("default:#{Discourse::PG_READONLY_MODE_KEY}") ? "1" : "0"
    end

    def test_redis(host, port, password)
      test_connection = Redis.new(host: host, port: port, password: password)
      test_connection.ping == "PONG" ? 1 : 0
    rescue
      0
    ensure
      test_connection.close
    end

    def recently_readonly?
      recently_readonly = "0"

      RailsMultisite::ConnectionManagement.with_connection('default') do
        recently_readonly = "1" if Discourse.recently_readonly?
      end

      recently_readonly
    end
  end
end
