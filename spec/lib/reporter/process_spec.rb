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

    context "job_exception_stats" do
      before do
        Discourse.reset_job_exception_stats!
      end

      after do
        Discourse.reset_job_exception_stats!
      end

      it "can collect job_exception_stats" do

        # see MiniScheduler Manager which reports it like this
        # https://github.com/discourse/mini_scheduler/blob/2b2c1c56b6e76f51108c2a305775469e24cf2b65/lib/mini_scheduler/manager.rb#L95
        exception_context = {
          message: "Running a scheduled job",
          job: { "class" => Jobs::ReindexSearch }
        }

        2.times do
          expect {
            Discourse.handle_job_exception(StandardError.new, exception_context)
          }.to raise_error(StandardError)
        end

        metric = Reporter::Process.new(:web).collect
        expect(metric.job_failures).to eq({
          { "job" => "Jobs::ReindexSearch" } => 2
        })
      end
    end

    it "can collect failover data" do
      metric = Reporter::Process.new(:web).collect

      expect(metric.active_record_failover_count).to eq(0)
      expect(metric.redis_failover_count).to eq(0)
    end
  end
end
