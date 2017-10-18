require 'raindrops'

module DiscoursePrometheus
  class MetricsController < ActionController::Base
    layout false

    def index
      redis_config = GlobalSetting.redis_config

      redis_master_running = test_redis(redis_config[:host], redis_config[:port], redis_config[:password])
      redis_slave_running = test_redis(redis_config[:slave_host], redis_config[:slave_port], redis_config[:password])

      net_stats = Raindrops::Linux::tcp_listener_stats("0.0.0.0:3000")["0.0.0.0:3000"]

      render plain: <<~TEXT
      # HELP web_postgres_readonly_mode Indicates whether site is in readonly mode due to PostgreSQL failover
      # TYPE web_postgres_readonly_mode gauge
      web_postgres_readonly_mode #{primary_site_readonly?}

      # HELP web_recently_readonly_mode Indicates whether site is in a transient readonly mode
      # TYPE web_recently_readonly_mode gauge
      web_recently_readonly_mode #{recently_readonly?}

      # HELP web_running_redis_masters Number of running redis masters in a web container
      # TYPE web_running_redis_masters gauge
      web_running_redis_masters #{redis_master_running}

      # HELP web_running_redis_slaves Number of running redis slaves in a web container
      # TYPE web_running_redis_slaves gauge
      web_running_redis_slaves #{redis_slave_running}

      # HELP web_active_app_reqs Number of active web requests
      # TYPE web_active_app_reqs gauge
      web_active_app_reqs #{net_stats.active}

      # HELP web_queued_app_reqs Number of active web requests
      # TYPE web_queued_app_reqs gauge
      web_queued_app_reqs #{net_stats.queued}

      # HELP web_sidekiq_jobs_enqueued
      # TYPE web_sidekiq_jobs_enqueued gauge
      web_sidekiq_jobs_enqueued #{Sidekiq::Stats.new.enqueued}

      # HELP web_sidekiq_processes
      # TYPE web_sidekiq_processes gauge
      web_sidekiq_processes #{Sidekiq::ProcessSet.new.size || 0}
      TEXT
    end

    private

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
