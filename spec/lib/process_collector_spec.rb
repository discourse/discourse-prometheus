require 'rails_helper'

module DiscoursePrometheus
  describe DiscoursePrometheus::Metric do
    def check_for(metric, *args)
      args.each do |arg|
        expect(metric.send arg).to be > 0
      end
    end

    it "Can collect gc stats" do
      ctx = MiniRacer::Context.new
      metric = ProcessCollector.new(:web).collect
      ctx.eval("")

      expect(metric.type).to eq(:web)
      check_for(metric, :heap_live_slots, :heap_free_slots, :major_gc_count,
        :minor_gc_count, :total_allocated_objects, :v8_heap_size,
        :v8_heap_count, :v8_physical_size, :pid, :rss)
    end
  end
end
