# frozen_string_literal: true

# collects stats from currently running process
module DiscoursePrometheus::Reporter
  class Process
    def self.start(client, type, frequency = 30)
      process_collector = new(type)

      Thread.new do
        while true
          begin
            metric = process_collector.collect
            client.send_json metric
          rescue => e
            Rails.logger.warn(
              "Prometheus Discourse Failed To Collect Process Stats #{e.class} #{e}\n#{e.backtrace.join("\n")}",
            )
          ensure
            sleep frequency
          end
        end
      end
    end

    def initialize(type)
      @type = type.to_s
    end

    def collect
      metric = ::DiscoursePrometheus::InternalMetric::Process.new
      metric.type = @type
      collect_gc_stats(metric)
      collect_v8_stats(metric)
      collect_process_stats(metric)
      collect_scheduler_stats(metric)
      collect_active_record_connections_stat(metric)
      collect_failover_stats(metric)
      metric
    end

    def pid
      @pid = ::Process.pid
    end

    def rss
      @pagesize ||=
        begin
          `getconf PAGESIZE`.to_i
        rescue StandardError
          4096
        end
      begin
        File.read("/proc/#{pid}/statm").split(" ")[1].to_i * @pagesize
      rescue StandardError
        0
      end
    end

    def collect_scheduler_stats(metric)
      metric.deferred_jobs_queued = Scheduler::Defer.length

      metric.job_failures = {}

      if Discourse.respond_to?(:job_exception_stats)
        Discourse.job_exception_stats.each do |klass, count|
          key = { "job" => klass.to_s }
          if klass.class == Class && klass < ::Jobs::Scheduled
            key["family"] = "scheduled"
          else
            # this is a guess, but regular jobs simply inherit off
            # Jobs::Base, so there is no easy way of finding out
            key["family"] = "regular"
          end
          metric.job_failures[key] = count
        end
      end
    end

    def collect_process_stats(metric)
      metric.pid = pid
      metric.rss = rss
      metric.thread_count = Thread.list.count
    end

    def collect_gc_stats(metric)
      stat = GC.stat
      metric.heap_live_slots = stat[:heap_live_slots]
      metric.heap_free_slots = stat[:heap_free_slots]
      metric.major_gc_count = stat[:major_gc_count]
      metric.minor_gc_count = stat[:minor_gc_count]

      if major_by = GC.latest_gc_info(:major_by)
        key = { reason: major_by.to_s }
        metric.gc_major_by[key] ||= 0
        metric.gc_major_by[key] += 1
      end

      metric.total_allocated_objects = stat[:total_allocated_objects]
    end

    def collect_v8_stats(metric)
      metric.v8_heap_count = metric.v8_heap_size = 0
      metric.v8_heap_size = metric.v8_physical_size = 0
      metric.v8_used_heap_size = 0

      ObjectSpace.each_object(MiniRacer::Context) do |context|
        stats = context.heap_stats
        if stats
          metric.v8_heap_count += 1
          metric.v8_heap_size += stats[:total_heap_size].to_i
          metric.v8_used_heap_size += stats[:used_heap_size].to_i
          metric.v8_physical_size += stats[:total_physical_size].to_i
        end
      end
    end

    def collect_active_record_connections_stat(metric)
      ObjectSpace.each_object(ActiveRecord::ConnectionAdapters::ConnectionPool) do |pool|
        if !pool.connections.nil?
          stat = pool.stat
          database = pool.db_config.database.to_s

          %i[busy dead idle waiting].each do |status|
            key = { status: status.to_s, database: database }

            metric.active_record_connections_count[key] ||= 0
            metric.active_record_connections_count[key] += stat[status]
          end
        end
      end
    end

    def collect_failover_stats(metric)
      if defined?(RailsFailover::ActiveRecord) &&
           RailsFailover::ActiveRecord::Handler.instance.respond_to?(:primaries_down_count)
        metric.active_record_failover_count =
          RailsFailover::ActiveRecord::Handler.instance.primaries_down_count
      end

      if defined?(RailsFailover::Redis) &&
           RailsFailover::Redis::Handler.instance.respond_to?(:primaries_down_count)
        metric.redis_failover_count = RailsFailover::Redis::Handler.instance.primaries_down_count
      end
    end
  end
end
