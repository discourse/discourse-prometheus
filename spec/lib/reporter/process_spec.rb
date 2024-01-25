# frozen_string_literal: true

require "rails_helper"

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

      GC.expects(:latest_gc_info).with(:major_by).returns(:nofree)

      metric = Reporter::Process.new(:web).collect

      expect(metric.type).to eq("web")
      expect(metric.gc_major_by).to eq({ { reason: "nofree" } => 1 })

      check_for(
        metric,
        :heap_live_slots,
        :heap_free_slots,
        :major_gc_count,
        :minor_gc_count,
        :total_allocated_objects,
        :v8_heap_size,
        :v8_heap_count,
        :v8_physical_size,
        :pid,
        :rss,
        :thread_count,
      )
    end

    describe "active_record_connections_count metric" do
      it "can collect active_record_connections_count" do
        metric = Reporter::Process.new(:web).collect

        database = ActiveRecord::Base.connection_pool.db_config.database

        expect(
          metric.active_record_connections_count[{ database: database, status: "busy" }],
        ).to be_present

        expect(
          metric.active_record_connections_count[{ database: database, status: "idle" }],
        ).to be_present

        expect(
          metric.active_record_connections_count[{ database: database, status: "dead" }],
        ).to be_present
        expect(
          metric.active_record_connections_count[{ database: database, status: "waiting" }],
        ).to be_present
      end
    end

    describe "job_exception_stats" do
      before { Discourse.reset_job_exception_stats! }

      after { Discourse.reset_job_exception_stats! }

      it "can collect job_exception_stats" do
        # see MiniScheduler Manager which reports it like this
        # https://github.com/discourse/mini_scheduler/blob/2b2c1c56b6e76f51108c2a305775469e24cf2b65/lib/mini_scheduler/manager.rb#L95
        exception_context = {
          message: "Running a scheduled job",
          job: {
            "class" => Jobs::ReindexSearch,
          },
        }

        2.times do
          expect {
            Discourse.handle_job_exception(StandardError.new, exception_context)
          }.to raise_error(StandardError)
        end

        metric = Reporter::Process.new(:web).collect
        expect(metric.job_failures).to eq(
          { { "job" => "Jobs::ReindexSearch", "family" => "scheduled" } => 2 },
        )
      end
    end

    it "can collect failover data" do
      metric = Reporter::Process.new(:web).collect

      expect(metric.active_record_failover_count).to eq(0)
      expect(metric.redis_failover_count).to eq(0)
    end
  end
end
