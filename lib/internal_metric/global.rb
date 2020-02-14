# frozen_string_literal: true

require 'raindrops'
require 'sidekiq/api'

module DiscoursePrometheus::InternalMetric
  class Global < Base

    def self.hostname
      @hostname ||=
        begin
          Discourse::Utils.execute_command("hostname").strip
        rescue
          "Unknown"
        end
    end

    STUCK_JOB_MINUTES = 60

    attribute :postgres_readonly_mode,
      :transient_readonly_mode,
      :redis_master_available,
      :redis_slave_available,
      :postgres_master_available,
      :postgres_replica_available,
      :active_app_reqs,
      :queued_app_reqs,
      :sidekiq_jobs_enqueued,
      :sidekiq_processes,
      :sidekiq_paused,
      :sidekiq_workers,
      :sidekiq_stuck_workers,
      :missing_post_uploads,
      :missing_s3_uploads,
      :version

    def initialize
      @active_app_reqs = 0
      @queued_app_reqs = 0
      @fault_logged = {}
      begin
        @version = `git rev-list --count HEAD`.to_i
      rescue
        @version = 0
      end
    end

    def collect
      redis_config = GlobalSetting.redis_config
      redis_master_running = test_redis(:master, redis_config[:host], redis_config[:port], redis_config[:password])
      redis_slave_running = 0

      postgres_master_running = test_postgres(master: true)
      postgres_replica_running = test_postgres(master: false)

      if redis_config[:slave_host]
        redis_slave_running = test_redis(:slave, redis_config[:slave_host], redis_config[:slave_port], redis_config[:password])
      end

      net_stats = Raindrops::Linux::tcp_listener_stats("0.0.0.0:3000")["0.0.0.0:3000"]

      @postgres_readonly_mode = primary_site_readonly?
      @transient_readonly_mode = recently_readonly?
      @redis_master_available = redis_master_running
      @redis_slave_available = redis_slave_running
      @postgres_master_available = postgres_master_running
      @postgres_replica_available = postgres_replica_running

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

      # not correct, should be per machine
      @sidekiq_workers = Sidekiq::ProcessSet.new.sum { |p| p["concurrency"] }

      @sidekiq_stuck_workers = Sidekiq::Workers.new.filter do |queue, _, w|
        queue.start_with?(Global.hostname) && Time.at(w["run_at"]) < (Time.now - 60 * STUCK_JOB_MINUTES)
      end.count

      @sidekiq_processes = (Sidekiq::ProcessSet.new.size || 0) rescue 0
      @sidekiq_paused = sidekiq_paused_states

      @missing_s3_uploads = missing_uploads("s3")
      @missing_post_uploads = missing_uploads("post")
    end

    private

    def primary_site_readonly?
      if !defined?(Discourse::PG_READONLY_MODE_KEY)
        return 1
      end
      if Discourse.redis.without_namespace.get("default:#{Discourse::PG_READONLY_MODE_KEY}")
        1
      else
        0
      end
    rescue
      0
    end

    def test_postgres(master: true)
      config = ActiveRecord::Base.connection_config

      unless master
        if config[:replica_host]
          config = config.dup.merge(
            host: config[:replica_host],
            port: config[:replica_port]
          )
        else
          return nil
        end
      end

      connection = ActiveRecord::Base.postgresql_connection(config)
      connection.active? ? 1 : 0
    rescue
      0
    ensure
      connection&.disconnect!
    end

    def test_redis(role, host, port, password)
      test_connection = Redis.new(host: host, port: port, password: password)
      if test_connection.ping == "PONG"
        1
      else
        0
      end
    rescue
      0
    ensure
      test_connection&.close
    end

    def recently_readonly?
      recently_readonly = 0

      RailsMultisite::ConnectionManagement.with_connection('default') do
        recently_readonly = 1 if Discourse.recently_readonly?
      end

      recently_readonly
    rescue
      # no db
      0
    end

    def sidekiq_paused_states
      paused = {}

      RailsMultisite::ConnectionManagement.each_connection do |db|
        paused[{ db: db }] = Sidekiq.paused? ? 1 : nil
      end

      paused
    end

    def missing_uploads(type)
      missing = {}

      if Discourse.respond_to?(:stats)
        begin
          RailsMultisite::ConnectionManagement.each_connection do |db|
            missing[{ db: db }] = Discourse.stats.get("missing_#{type}_uploads")
          end
        rescue => e
          Discourse.warn_exception(e, message: "Failed to connect to database to collect upload stats")
        end
      end

      missing
    end
  end
end
