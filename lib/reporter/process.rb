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
            Rails.logger.warn("Prometheus Discourse Failed To Collect Process Stats #{e.class} #{e}\n#{e.backtrace.join("\n")}")
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
      collect_readonly_mode_stats(metric)
      metric
    end

    def pid
      @pid = ::Process.pid
    end

    def rss
      @pagesize ||= `getconf PAGESIZE`.to_i rescue 4096
      File.read("/proc/#{pid}/statm").split(' ')[1].to_i * @pagesize rescue 0
    end

    def collect_scheduler_stats(metric)
      metric.deferred_jobs_queued = Scheduler::Defer.length
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

          %i{busy dead idle waiting}.each do |status|
            key = { status: status.to_s }
            metric.active_record_connections_count[key] ||= 0
            metric.active_record_connections_count[key] += stat[status]
          end
        end
      end
    end

    def collect_readonly_mode_stats(metric)
      dbs = RailsMultisite::ConnectionManagement.all_dbs

      # Dispose of old data
      metric.readonly = {}
      metric.last_readonly_seconds = {}

      # This readonly info exists in redis. In theory it should be consistent across all processes
      # But if some processes have failed over to the redis replica, there could be discrepencies
      Discourse::READONLY_KEYS.each do |key|
        redis_keys = dbs.map { |db| "#{db}:#{key}" }
        redis_values = Discourse.redis.without_namespace.mget(redis_keys)
        dbs.each_with_index do |db, index|
          metric.readonly[{ key: key, db: db }] = redis_values[index].to_i
        end
      end

      # This readonly info is stored in the local process.
      # postgres_last_read_only should be synced via DistributedCache, but this is not guaranteed
      dbs.each do |db|
        metric.last_readonly_seconds[{ store: "postgres", db: db }] = Discourse.postgres_last_read_only[db].to_i
        metric.last_readonly_seconds[{ store: "redis", db: db }] = Discourse.redis_last_read_only[db].to_i
      end
    end
  end
end
