# frozen_string_literal: true

require 'raindrops'
require 'sidekiq/api'

module DiscoursePrometheus::InternalMetric
  class Global < Base

    attribute :postgres_readonly_mode,
      :transient_readonly_mode,
      :redis_master_available,
      :redis_slave_available,
      :postgresql_master_available,
      :postgresql_replica_available,
      :active_app_reqs,
      :queued_app_reqs,
      :sidekiq_jobs_enqueued,
      :sidekiq_processes

    def initialize
      @active_app_reqs = 0
      @queued_app_reqs = 0

      @fault_logged = {}
    end

    def collect
      redis_config = GlobalSetting.redis_config
      redis_master_running = test_redis(:master, redis_config[:host], redis_config[:port], redis_config[:password])
      redis_slave_running = 0

      postgresql_master_running = test_postgresql(master: true)
      postgresql_replica_running = test_postgresql(master: false)

      if redis_config[:slave_host]
        redis_slave_running = test_redis(:slave, redis_config[:slave_host], redis_config[:slave_port], redis_config[:password])
      end

      net_stats = Raindrops::Linux::tcp_listener_stats("0.0.0.0:3000")["0.0.0.0:3000"]

      @postgres_readonly_mode = primary_site_readonly?
      @transient_readonly_mode = recently_readonly?
      @redis_master_available = redis_master_running
      @redis_slave_available = redis_slave_running
      @postgresql_master_available = postgresql_master_running
      @postgresql_replica_available = postgresql_replica_running

      # active and queued are special metrics that track max
      @active_app_reqs = [@active_app_reqs, net_stats.active].max
      @queued_app_reqs = [@queued_app_reqs, net_stats.queued].max

      @sidekiq_jobs_enqueued = begin
        stats = {}

        Sidekiq::Stats.new.queues.each do |queue_name, queue_count|
          stats[{ queue: queue_name }] = queue_count
        end

        stats
      end

      @sidekiq_processes = (Sidekiq::ProcessSet.new.size || 0) rescue 0
    end

    private

    def primary_site_readonly?
      fault_log_key = :primary_site_readonly

      unless defined?(Discourse::PG_READONLY_MODE_KEY)
        conditionally_log_fault(fault_log_key, "Declared primary site read-only due to Discourse::PG_READONLY_MODE_KEY not being defined")
        return 1
      end
      if $redis.without_namespace.get("default:#{Discourse::PG_READONLY_MODE_KEY}")
        conditionally_log_fault(fault_log_key, "Declared primary site read-only due to default:#{Discourse::PG_READONLY_MODE_KEY} being set")
        1
      else
        clear_fault_log(fault_log_key)
        0
      end
    rescue
      clear_fault_log(fault_log_key)
      0
    end

    def test_postgresql(master: true)
      config = ActiveRecord::Base.connection_config

      unless master
        if config[:replica_host]
          config = config.dup.merge(
            host: config[:replica_host],
            port: config[:replica_port]
          )
        else
          return 0
        end
      end

      connection = ActiveRecord::Base.postgresql_connection(config)
      connection.active? ? 1 : 0
    rescue => ex
      role = master ? 'master' : 'replica'
      conditionally_log_fault(:"test_postgresql_#{role}", (["Declared PostgreSQL #{role} down due to exception: #{ex.message} (#{ex.class})"] + ex.backtrace).join("\n  "))
      0
    ensure
      connection&.disconnect!
    end

    def test_redis(role, host, port, password)
      fault_log_key = :"test_redis_#{role}"

      test_connection = Redis.new(host: host, port: port, password: password)
      if test_connection.ping == "PONG"
        clear_fault_log(fault_log_key)
        1
      else
        conditionally_log_fault(fault_log_key, "Declared Redis #{role} down because PING/PONG failed")
        0
      end
    rescue => ex
      conditionally_log_fault(fault_log_key, (["Declared Redis #{role} down due to exception: #{ex.message} (#{ex.class})"] + ex.backtrace).join("\n  "))
      0
    ensure
      test_connection&.close
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

    def conditionally_log_fault(key, msg)
      unless @fault_logged[key]
        Rails.logger.error(msg)
        @fault_logged[key] = true
      end
    end

    def clear_fault_log(key)
      @fault_logged[key] = false
    end
  end
end
