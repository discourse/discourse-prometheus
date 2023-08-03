# frozen_string_literal: true

module DiscoursePrometheus::InternalMetric
  class Process < Base
    GAUGES = {
      gc_major_by: "Reason the last major GC was triggered",
      heap_free_slots: "Free ruby heap slots",
      heap_live_slots: "Used ruby heap slots",
      v8_heap_size: "Total JavaScript V8 heap size (bytes)",
      v8_used_heap_size: "Total used JavaScript V8 heap size (bytes)",
      v8_physical_size: "Physical size consumed by V8 heaps",
      v8_heap_count: "Number of V8 contexts running",
      rss: "Total RSS used by process",
      thread_count: "Total number of active threads per process",
      deferred_jobs_queued: "Number of jobs queued in the deferred job queue",
      active_record_connections_count:
        "Total number of connections in ActiveRecord's connection pools",
      active_record_failover_count: "Count of ActiveRecord databases in a failover state",
      redis_failover_count: "Count of Redis servers in a failover state",
    }

    COUNTERS = {
      major_gc_count: "Major GC operations by process",
      minor_gc_count: "Minor GC operations by process",
      total_allocated_objects: "Total number of allocateds objects by process",
      job_failures: "Number of scheduled and regular jobs that failed in a process",
    }

    attribute :type,
              :gc_major_by,
              :heap_free_slots,
              :heap_live_slots,
              :major_gc_count,
              :minor_gc_count,
              :total_allocated_objects,
              :rss,
              :thread_count,
              :v8_heap_size,
              :v8_used_heap_size,
              :v8_physical_size,
              :v8_heap_count,
              :pid,
              :created_at,
              :deferred_jobs_queued,
              :active_record_connections_count,
              :active_record_failover_count,
              :redis_failover_count,
              :job_failures

    def initialize
      @active_record_connections_count = {}
      @gc_major_by = {}
    end
  end
end
