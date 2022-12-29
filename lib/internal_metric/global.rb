# frozen_string_literal: true

require "raindrops"
require "sidekiq/api"
require "open3"

module DiscoursePrometheus::InternalMetric
  class Global < Base
    STUCK_SIDEKIQ_JOB_MINUTES = 120

    attribute :postgres_readonly_mode,
              :redis_master_available,
              :redis_slave_available,
              :redis_primary_available,
              :redis_replica_available,
              :postgres_master_available,
              :postgres_primary_available,
              :postgres_replica_available,
              :active_app_reqs,
              :queued_app_reqs,
              :sidekiq_jobs_enqueued,
              :sidekiq_processes,
              :sidekiq_paused,
              :sidekiq_workers,
              :sidekiq_jobs_stuck,
              :scheduled_jobs_stuck,
              :missing_s3_uploads,
              :version_info,
              :readonly_sites

    def initialize
      @active_app_reqs = 0
      @queued_app_reqs = 0
      @fault_logged = {}

      begin
        @@version = nil

        out, error, status = Open3.capture3("git rev-parse HEAD")

        if status.success?
          @@version ||= out.chomp
        else
          raise error
        end
      rescue => e
        if defined?(::Discourse)
          Discourse.warn_exception(e, message: "Failed to calculate discourse_version_info metric")
        else
          STDERR.puts "Failed to calculate discourse_version_info metric: #{e}\n#{e.backtrace.join("\n")}"
        end

        @@retries ||= 10
        @@retries -= 1
        @@version = -1 if @@retries < 0
      end
    end

    def collect
      @version_info ||= { { revision: @@version, version: Discourse::VERSION::STRING } => 1 }

      redis_primary_running = {}
      redis_replica_running = {}

      redis_config = GlobalSetting.redis_config
      redis_primary_running[{ type: "main" }] = test_redis(
        :master,
        host: redis_config[:host],
        port: redis_config[:port],
        password: redis_config[:password],
        ssl: redis_config[:ssl],
      )
      redis_replica_running[{ type: "main" }] = 0

      if redis_config[:replica_host]
        redis_replica_running[{ type: "main" }] = test_redis(
          :slave,
          host: redis_config[:replica_host],
          port: redis_config[:replica_port],
          password: redis_config[:password],
          ssl: redis_config[:ssl],
        )
      else
        redis_replica_running[{ type: "main" }] = 0
      end

      if GlobalSetting.message_bus_redis_enabled
        mb_redis_config = GlobalSetting.message_bus_redis_config
        redis_primary_running[{ type: "message-bus" }] = test_redis(
          :master,
          host: mb_redis_config[:host],
          port: mb_redis_config[:port],
          password: mb_redis_config[:password],
          ssl: mb_redis_config[:ssl],
        )
        redis_replica_running[{ type: "message-bus" }] = 0

        if mb_redis_config[:replica_host]
          redis_replica_running[{ type: "message-bus" }] = test_redis(
            :slave,
            host: mb_redis_config[:replica_host],
            port: mb_redis_config[:replica_port],
            password: mb_redis_config[:password],
            ssl: mb_redis_config[:ssl],
          )
        else
          redis_replica_running[{ type: "message-bus" }] = 0
        end
      end

      postgres_primary_running = test_postgres(primary: true)
      postgres_replica_running = test_postgres(primary: false)

      net_stats = nil

      if RbConfig::CONFIG["arch"] !~ /darwin/
        if listener = ENV["UNICORN_LISTENER"]
          net_stats = Raindrops::Linux.unix_listener_stats([listener])[listener]
        else
          net_stats = Raindrops::Linux.tcp_listener_stats("0.0.0.0:3000")["0.0.0.0:3000"]
        end
      end

      @postgres_readonly_mode = primary_site_readonly?
      @redis_primary_available = @redis_master_available = redis_primary_running
      @redis_replica_available = @redis_slave_available = redis_replica_running
      @postgres_primary_available = @postgres_master_available = postgres_primary_running
      @postgres_replica_available = postgres_replica_running

      # active and queued are special metrics that track max
      @active_app_reqs = [@active_app_reqs, net_stats.active].max if net_stats
      @queued_app_reqs = [@queued_app_reqs, net_stats.queued].max if net_stats

      @sidekiq_jobs_enqueued =
        begin
          stats = {}

          Sidekiq::Stats.new.queues.each do |queue_name, queue_count|
            stats[{ queue: queue_name }] = queue_count
          end

          stats
        end

      hostname = ::PrometheusExporter.hostname

      @sidekiq_processes = 0
      @sidekiq_workers =
        Sidekiq::ProcessSet
          .new(false)
          .sum do |process|
            if process["hostname"] == hostname
              @sidekiq_processes += 1
              process["concurrency"]
            else
              0
            end
          end

      @sidekiq_jobs_stuck = find_stuck_sidekiq_jobs
      @scheduled_jobs_stuck = find_stuck_scheduled_jobs

      @sidekiq_paused = sidekiq_paused_states

      @missing_s3_uploads = missing_uploads("s3")

      @readonly_sites = collect_readonly_sites
    end

    # For testing purposes
    def reset!
      @@missing_uploads = nil
    end

    private

    def collect_readonly_sites
      dbs = RailsMultisite::ConnectionManagement.all_dbs
      result = {}

      Discourse::READONLY_KEYS.each do |key|
        redis_keys = dbs.map { |db| "#{db}:#{key}" }
        count = Discourse.redis.without_namespace.exists(*redis_keys)
        result[{ key: key }] = count
      end

      result
    end

    def primary_site_readonly?
      return 1 if !defined?(Discourse::PG_READONLY_MODE_KEY)
      Discourse.redis.without_namespace.get("default:#{Discourse::PG_READONLY_MODE_KEY}") ? 1 : 0
    rescue StandardError
      0
    end

    def test_postgres(primary: true)
      config = ActiveRecord::Base.connection_db_config.configuration_hash

      unless primary
        if config[:replica_host]
          config = config.dup.merge(host: config[:replica_host], port: config[:replica_port])
        else
          return nil
        end
      end

      connection = ActiveRecord::Base.postgresql_connection(config)
      connection.active? ? 1 : 0
    rescue StandardError
      0
    ensure
      connection&.disconnect!
    end

    def test_redis(role, **config)
      test_connection = Redis.new(**config)
      if test_connection.ping == "PONG"
        1
      else
        0
      end
    rescue StandardError
      0
    ensure
      test_connection&.close
    end

    def sidekiq_paused_states
      paused = {}

      begin
        RailsMultisite::ConnectionManagement.each_connection do |db|
          paused[{ db: db }] = Sidekiq.paused? ? 1 : nil
        end
      rescue => e
        Discourse.warn_exception(e, message: "Failed to connect to redis to collect paused status")
      end

      paused
    end

    MISSING_UPLOADS_CHECK_SECONDS = 60

    def missing_uploads(type)
      @@missing_uploads ||= {}
      @@missing_uploads[type] ||= {}
      @@missing_uploads[type][:stats] ||= {}
      last_check = @@missing_uploads[type][:last_check]

      if Discourse.respond_to?(:stats) &&
           (!last_check || (Time.now.to_i - last_check > MISSING_UPLOADS_CHECK_SECONDS))
        begin
          RailsMultisite::ConnectionManagement.each_connection do |db|
            next if !SiteSetting.enable_s3_inventory
            @@missing_uploads[type][:stats][{ db: db }] = Discourse.stats.get(
              "missing_#{type}_uploads",
            )
          end

          @@missing_uploads[type][:last_check] = Time.now.to_i
        rescue => e
          if @postgres_master_available == 1
            Discourse.warn_exception(
              e,
              message: "Failed to connect to database to collect upload stats",
            )
          else
            # TODO: Be smarter and connect to the replica. For now, just disable
            # the noise when we failover.
          end
        end
      end

      @@missing_uploads[type][:stats]
    end

    def find_stuck_scheduled_jobs
      hostname = ::PrometheusExporter.hostname
      stats = {}
      MiniScheduler::Manager.discover_schedules.each do |klass|
        info_key =
          (
            if klass.is_per_host
              MiniScheduler::Manager.schedule_key(klass, hostname)
            else
              MiniScheduler::Manager.schedule_key(klass)
            end
          )
        schedule_info = Discourse.redis.get(info_key)
        schedule_info =
          begin
            JSON.parse(schedule_info, symbolize_names: true)
          rescue StandardError
            nil
          end

        next if !schedule_info
        next if !schedule_info[:prev_result] == "RUNNING" # Only look at jobs which are running
        next if !schedule_info[:current_owner]&.start_with?("_scheduler_#{hostname}") # Only look at jobs on this host

        job_frequency = klass.every || 1.day
        started_at = Time.at(schedule_info[:prev_run])

        allowed_duration =
          begin
            if job_frequency < 30.minutes
              30.minutes
            elsif job_frequency < 2.hours
              job_frequency
            else
              2.hours
            end
          end

        next unless started_at < (Time.now - allowed_duration)

        labels = { job_name: klass.name }
        stats[labels] ||= 0
        stats[labels] += 1
      end
      stats
    rescue => e
      Discourse.warn_exception(
        e,
        message: "Failed to connect to redis to collect scheduled job status",
      )
    end

    def find_stuck_sidekiq_jobs
      hostname = ::PrometheusExporter.hostname
      stats = {}
      Sidekiq::Workers.new.each do |queue, tid, work|
        next unless queue.start_with?(hostname)
        next unless Time.at(work["run_at"]) < (Time.now - 60 * STUCK_SIDEKIQ_JOB_MINUTES)
        labels = { job_name: work.dig("payload", "class") }
        stats[labels] ||= 0
        stats[labels] += 1
      end
      stats
    end
  end
end
