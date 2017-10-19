require 'raindrops'

module DiscoursePrometheus
  class MetricsController < ActionController::Base
    layout false

    def index
      redis_config = GlobalSetting.redis_config

      redis_master_running = test_redis(redis_config[:host], redis_config[:port], redis_config[:password])
      redis_slave_running = 0

      if redis_config[:slave_host]
        test_redis(redis_config[:slave_host], redis_config[:slave_port], redis_config[:password])
      end

      net_stats = Raindrops::Linux::tcp_listener_stats("0.0.0.0:3000")["0.0.0.0:3000"]

      @metrics = []

      add_gauge(
        "postgres_readonly_mode",
        "Indicates whether site is in readonly mode due to PostgreSQL failover",
        primary_site_readonly?
      )

      add_gauge(
        "recently_readonly_mode",
        "Indicates whether site is in a transient readonly mode",
        recently_readonly?
      )

      add_gauge(
        "running_redis_masters",
        "Number of running redis masters in a web container",
        redis_master_running
      )

      add_gauge(
        "running_redis_slaves",
        "Number of running redis slaves in a web container",
        redis_slave_running
      )

      add_gauge(
        "active_app_reqs",
        "Number of active web requests",
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

      add_request_metrics

      render plain: <<~TEXT
      #{@metrics.map(&:to_prometheus_text).join("\n\n")}
      TEXT
    end

    private

      def add_request_metrics
        Processor.process($prometheus_pipe.process.to_enum).each do |metric|
          @metrics << metric
        end
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
      rescue Redis::CannotConnectError
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
