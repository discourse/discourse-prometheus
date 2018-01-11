# frozen_string_literal: true

require 'raindrops'

module DiscoursePrometheus::InternalMetric
  class Global < Base

    attribute :postgres_readonly_mode,
      :transient_readonly_mode,
      :redis_master_available,
      :redis_slave_available,
      :active_app_reqs,
      :queued_app_reqs,
      :sidekiq_jobs_enqueued,
      :sidekiq_processes

    def initialize
      @active_app_reqs = 0
      @queued_app_reqs = 0
    end

    def collect
      redis_config = GlobalSetting.redis_config
      redis_master_running = test_redis(redis_config[:host], redis_config[:port], redis_config[:password])
      redis_slave_running = 0

      if redis_config[:slave_host]
        redis_slave_running = test_redis(redis_config[:slave_host], redis_config[:slave_port], redis_config[:password])
      end

      net_stats = Raindrops::Linux::tcp_listener_stats("0.0.0.0:3000")["0.0.0.0:3000"]

      @postgres_readonly_mode = primary_site_readonly?
      @transient_readonly_mode = recently_readonly?
      @redis_master_available = redis_master_running
      @redis_slave_available = redis_slave_running

      # active and queued are special metrics that track max
      @active_app_reqs = [@active_app_reqs, net_stats.active].max
      @queued_app_reqs = [@queued_app_reqs, net_stats.queued].max

      @sidekiq_jobs_enqueued = (Sidekiq::Stats.new.enqueued) rescue 0
      @sidekiq_processes = (Sidekiq::ProcessSet.new.size || 0) rescue 0
    end

    private

    def primary_site_readonly?
      return 1 unless defined?(Discourse::PG_READONLY_MODE_KEY)
      $redis.without_namespace.get("default:#{Discourse::PG_READONLY_MODE_KEY}") ? 1 : 0
    rescue
      0
    end

    def test_redis(host, port, password)
      test_connection = Redis.new(host: host, port: port, password: password)
      test_connection.ping == "PONG" ? 1 : 0
    rescue
      0
    ensure
      test_connection.close rescue nil
    end

    def recently_readonly?
      recently_readonly = 0

      RailsMultisite::ConnectionManagement.with_connection('default') do
        recently_readonly = 1 if Discourse.recently_readonly?
      end
      ActiveRecord::Base.connection_handler.clear_active_connections!

      recently_readonly
    rescue
      # no db
      0
    end
  end
end
