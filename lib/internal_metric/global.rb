# frozen_string_literal: true

require 'raindrops'
require 'sidekiq/api'
require 'open3'

module DiscoursePrometheus::InternalMetric
  class Global < Base

    STUCK_SIDEKIQ_JOB_MINUTES = 120

    attribute :postgres_readonly_mode,
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
      :sidekiq_jobs_stuck,
      :scheduled_jobs_stuck,
      :missing_s3_uploads,
      :version

    def initialize
      @active_app_reqs = 0
      @queued_app_reqs = 0
      @fault_logged = {}

      begin
        @@version = nil

        out, error, status = Open3.capture3('git rev-list --count HEAD')

        if status.success?
          @@version ||= out.to_i
        else
          raise error
        end
      rescue => e
        if defined?(::Discourse)
          Discourse.warn_exception(e, message: "Failed to calculate discourse_version metric")
        else
          STDERR.puts "Failed to calculate discourse_version metric: #{e}\n#{e.backtrace.join("\n")}"
        end

        @@retries ||= 10
        @@retries -= 1
        if @@retries < 0
          @@version = -1
        end
      end

      @version = @@version || -2
    end

    def collect
      redis_config = GlobalSetting.redis_config
      redis_master_running = test_redis(:master, redis_config[:host], redis_config[:port], redis_config[:password])
      redis_slave_running = 0

      postgres_master_running = test_postgres(master: true)
      postgres_replica_running = test_postgres(master: false)

      redis_slave_host = redis_config[:slave_host] || redis_config[:replica_host]
      redis_slave_port = redis_config[:slave_port] || redis_config[:replica_port]

      if redis_slave_host
        redis_slave_running = test_redis(:slave, redis_slave_host, redis_slave_port, redis_config[:password])
      end

      net_stats = nil

      if RbConfig::CONFIG["arch"] !~ /darwin/
        if listener = ENV["UNICORN_LISTENER"]
          net_stats = Raindrops::Linux::unix_listener_stats([listener])[listener]
        else
          net_stats = Raindrops::Linux::tcp_listener_stats("0.0.0.0:3000")["0.0.0.0:3000"]
        end
      end

      @postgres_readonly_mode = primary_site_readonly?
      @redis_master_available = redis_master_running
      @redis_slave_available = redis_slave_running
      @postgres_master_available = postgres_master_running
      @postgres_replica_available = postgres_replica_running

      # active and queued are special metrics that track max
      @active_app_reqs = [@active_app_reqs, net_stats.active].max if net_stats
      @queued_app_reqs = [@queued_app_reqs, net_stats.queued].max if net_stats

      @sidekiq_jobs_enqueued = begin
        stats = {}

        Sidekiq::Stats.new.queues.each do |queue_name, queue_count|
          stats[{ queue: queue_name }] = queue_count
        end

        stats
      end

      hostname = ::PrometheusExporter.hostname

      @sidekiq_processes = 0
      @sidekiq_workers = Sidekiq::ProcessSet.new(false).sum do |process|
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
    end

    # For testing purposes
    def reset!
      @@missing_uploads = nil
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

      if Discourse.respond_to?(:stats) && (!last_check || (Time.now.to_i - last_check > MISSING_UPLOADS_CHECK_SECONDS))
        begin
          RailsMultisite::ConnectionManagement.each_connection do |db|
            @@missing_uploads[type][:stats][{ db: db }] = Discourse.stats.get("missing_#{type}_uploads")
          end

          @@missing_uploads[type][:last_check] = Time.now.to_i
        rescue => e
          if @postgres_master_available == 1
            Discourse.warn_exception(e, message: "Failed to connect to database to collect upload stats")
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
        info_key = klass.is_per_host ? MiniScheduler::Manager.schedule_key(klass, hostname) : MiniScheduler::Manager.schedule_key(klass)
        schedule_info = Discourse.redis.get(info_key)
        schedule_info = JSON.parse(schedule_info, symbolize_names: true) rescue nil

        next if !schedule_info
        next if !schedule_info[:prev_result] == "RUNNING" # Only look at jobs which are running
        next if !schedule_info[:current_owner]&.start_with?("_scheduler_#{hostname}") # Only look at jobs on this host

        job_frequency = klass.every || 1.day
        started_at = Time.at(schedule_info[:prev_run])

        allowed_duration = begin
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
      Discourse.warn_exception(e, message: "Failed to connect to redis to collect scheduled job status")
    end

    def find_stuck_sidekiq_jobs
      hostname = ::PrometheusExporter.hostname
      stats = {}
      Sidekiq::Workers.new.each do |queue, tid, work|
        next unless queue.start_with?(hostname)
        next unless Time.at(work["run_at"]) < (Time.now - 60 * STUCK_SIDEKIQ_JOB_MINUTES)
        labels = { job_name: work.dig('payload', 'class') }
        stats[labels] ||= 0
        stats[labels] += 1
      end
      stats
    end
  end
end
