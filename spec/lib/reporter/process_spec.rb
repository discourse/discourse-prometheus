# frozen_string_literal: true

require 'rails_helper'

module DiscoursePrometheus
  describe Reporter::Process do
    def check_for(metric, *args)
      args.each do |arg|
        next if arg == :rss && RbConfig::CONFIG["arch"] =~ /darwin/ # macos does not support these metrics
        expect(metric.send arg).to be > 0
      end
    end

    it "Can collect gc stats" do
      ctx = MiniRacer::Context.new
      ctx.eval("")

      metric = Reporter::Process.new(:web).collect

      expect(metric.type).to eq('web')

      check_for(metric, :heap_live_slots, :heap_free_slots, :major_gc_count,
        :minor_gc_count, :total_allocated_objects, :v8_heap_size,
        :v8_heap_count, :v8_physical_size, :pid, :rss, :thread_count)
    end
  end
end
