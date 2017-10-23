# frozen_string_literal: true
#
module DiscoursePrometheus
  class ProcessMetric

    GAUGES = {
      heap_free_slots: "Free ruby heap slots",
      heap_live_slots: "Used ruby heap slots",
      v8_heap_size: "Total JavaScript V8 heap size (bytes)",
      v8_used_heap_size: "Total used JavaScript V8 heap size (bytes)",
      v8_physical_size: "Physical size consumed by V8 heaps",
      v8_heap_count: "Number of V8 contexts running",
      rss: "Total RSS used by process"
    }

    COUNTERS = {
      major_gc_count: "Major GC operations by process",
      minor_gc_count: "Minor GC operations by process",
      total_allocated_objects: "Total number of allocateds objects by process",
    }

    attr_accessor :type,
      :heap_free_slots,
      :heap_live_slots,
      :major_gc_count,
      :minor_gc_count,
      :total_allocated_objects,
      :rss,
      :v8_heap_size,
      :v8_used_heap_size,
      :v8_physical_size,
      :v8_heap_count,
      :pid,
      :created_at

    def initialize
      @created_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
