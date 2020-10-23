# frozen_string_literal: true

module DiscoursePrometheus::InternalMetric
  class Process < Base

    GAUGES = {
      heap_free_slots: "Free ruby heap slots",
      heap_live_slots: "Used ruby heap slots",
      v8_heap_size: "Total JavaScript V8 heap size (bytes)",
      v8_used_heap_size: "Total used JavaScript V8 heap size (bytes)",
      v8_physical_size: "Physical size consumed by V8 heaps",
      v8_heap_count: "Number of V8 contexts running",
      rss: "Total RSS used by process",
      thread_count: "Total number of active threads per process",
      deferred_jobs_queued: "Number of jobs queued in the deferred job queue",
      active_record_connections_count: "Total number of connections in ActiveRecord's connection pools",
      readonly_sites_count: "Number of sites currently in readonly mode. Key is one of Discourse::READONLY_KEYS, 'redis_recently_readonly' or 'postgres_recently_readonly'"
    }

    COUNTERS = {
      major_gc_count: "Major GC operations by process",
      minor_gc_count: "Minor GC operations by process",
      total_allocated_objects: "Total number of allocateds objects by process",
    }

    attribute :type,
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
      :readonly_sites_count

    def initialize
      @active_record_connections_count = {}
    end
  end
end
