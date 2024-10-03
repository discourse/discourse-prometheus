# frozen_string_literal: true

RSpec.describe DiscoursePrometheus::Reporter::Process do
  it "collects gc stats" do
    ctx = MiniRacer::Context.new
    ctx.eval("")

    GC.expects(:latest_gc_info).with(:major_by).returns(:nofree)

    metric = described_class.new(:web).collect

    expect(metric.type).to eq("web")
    expect(metric.gc_major_by).to eq({ { reason: "nofree" } => 1 })

    expect(metric.heap_live_slots).to be > 0
    expect(metric.heap_free_slots).to be > 0
    expect(metric.major_gc_count).to be > 0
    expect(metric.minor_gc_count).to be > 0
    expect(metric.total_allocated_objects).to be > 0
    expect(metric.v8_heap_size).to be > 0
    expect(metric.v8_heap_count).to be > 0
    expect(metric.v8_physical_size).to be > 0
    expect(metric.pid).to be > 0
    expect(metric.thread_count).to be > 0

    # macos does not support these metrics
    expect(metric.rss).to be > 0 unless RbConfig::CONFIG["arch"] =~ /darwin/
  end

  describe "job_exception_stats" do
    before { Discourse.reset_job_exception_stats! }
    after { Discourse.reset_job_exception_stats! }

    it "collects job_exception_stats" do
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

      metric = described_class.new(:web).collect
      expect(metric.job_failures).to eq(
        { { "job" => "Jobs::ReindexSearch", "family" => "scheduled" } => 2 },
      )
    end
  end

  it "collects failover data" do
    metric = described_class.new(:web).collect

    expect(metric.active_record_failover_count).to eq(0)
    expect(metric.redis_failover_count).to eq(0)
  end
end
