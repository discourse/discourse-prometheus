# frozen_string_literal: true

RSpec.describe DiscoursePrometheus::Reporter::Process do
  describe "#collect" do
    it "collects YJIT state, memory usage, and compilation failures for web workers" do
      RubyVM::YJIT.stubs(:enabled?).returns(true)
      RubyVM::YJIT.stubs(:runtime_stats).returns(
        { code_region_size: 1024, yjit_alloc_size: 2048, compilation_failure: 3 },
      )

      metric = described_class.new(:web).collect

      expect(metric).to have_attributes(
        yjit_enabled: 1,
        yjit_code_region_size_bytes: 1024,
        yjit_alloc_size_bytes: 2048,
        yjit_compilation_failure_total: 3,
      )
    end

    it "reports disabled YJIT without fabricating memory or failure values" do
      RubyVM::YJIT.stubs(:enabled?).returns(false)
      RubyVM::YJIT.stubs(:runtime_stats).returns(nil)

      metric = described_class.new(:web).collect

      expect(metric).to have_attributes(
        yjit_enabled: 0,
        yjit_code_region_size_bytes: nil,
        yjit_alloc_size_bytes: nil,
        yjit_compilation_failure_total: nil,
      )
      expect(metric.process_cpu_seconds_total).to be >= 0
    end

    it "reports disabled YJIT when Ruby was built without it" do
      hide_const("RubyVM::YJIT")

      metric = described_class.new(:web).collect

      expect(metric.yjit_enabled).to eq(0)
      expect(metric.pid).to eq(Process.pid)
    end

    it "omits unavailable YJIT statistics" do
      RubyVM::YJIT.stubs(:enabled?).returns(true)
      RubyVM::YJIT.stubs(:runtime_stats).returns({ code_region_size: 0 })

      metric = described_class.new(:web).collect

      expect(metric).to have_attributes(
        yjit_enabled: 1,
        yjit_code_region_size_bytes: 0,
        yjit_alloc_size_bytes: nil,
        yjit_compilation_failure_total: nil,
      )
    end

    it "leaves YJIT metrics unset for Sidekiq processes" do
      RubyVM::YJIT.stubs(:enabled?).returns(true)
      RubyVM::YJIT.stubs(:runtime_stats).returns(
        { code_region_size: 1024, yjit_alloc_size: 2048, compilation_failure: 3 },
      )

      metric = described_class.new(:sidekiq).collect

      expect(metric).to have_attributes(
        yjit_enabled: nil,
        yjit_code_region_size_bytes: nil,
        yjit_alloc_size_bytes: nil,
        yjit_compilation_failure_total: nil,
      )
    end
  end

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
    expect(metric.process_cpu_seconds_total).to be > 0

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
