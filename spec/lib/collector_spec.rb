# frozen_string_literal: true

require "prometheus_exporter/server"
require_relative "../../lib/collector"

RSpec.describe DiscoursePrometheus::Collector do
  subject(:collector) { described_class.new }

  it "processes custom metrics" do
    collector.process(<<~METRIC)
        {
          "_type": "Custom",
          "name": "counter",
          "description": "some description",
          "value": 2,
          "type": "Counter"
        }
      METRIC

    collector.process(<<~METRIC)
        {
          "_type": "Custom",
          "name": "counter",
          "description": "some description",
          "type": "Counter"
        }
      METRIC

    collector.process(<<~METRIC)
        {
          "_type": "Custom",
          "name": "gauge",
          "labels": { "test": "super" },
          "description": "some description",
          "value": 122.1,
          "type": "Gauge"
        }
      METRIC

    metrics = collector.prometheus_metrics

    counter = metrics.find { |m| m.name == "counter" }
    gauge = metrics.find { |m| m.name == "gauge" }

    expect(gauge.data).to eq({ "test" => "super" } => 122.1)
    expect(counter.data).to eq(nil => 3)
  end

  it "handles sidekiq job metrics" do
    metric_1 = DiscoursePrometheus::InternalMetric::Job.new
    metric_1.scheduled = false
    metric_1.job_name = "Bob"
    metric_1.duration = 1.778
    metric_1.count = 1
    metric_1.success = true

    collector.process(metric_1.to_json)
    metrics = collector.prometheus_metrics

    metric_2 = DiscoursePrometheus::InternalMetric::Job.new
    metric_2.scheduled = false
    metric_2.job_name = "Bob"
    metric_2.duration = 0.5
    metric_2.count = 1
    metric_2.success = false
    collector.process(metric_2.to_json)

    metric_3 = DiscoursePrometheus::InternalMetric::Job.new
    metric_3.scheduled = false
    metric_3.job_name = "Bob"
    metric_3.duration = 1.5
    metric_3.count = 1
    metric_3.success = false
    collector.process(metric_3.to_json)

    duration = metrics.find { |m| m.name == "sidekiq_job_duration_seconds" }
    sidekiq_job_count = metrics.find { |m| m.name == "sidekiq_job_count" }

    expect(duration.data).to eq(
      { job_name: "Bob", success: true } => metric_1.duration,
      { job_name: "Bob", success: false } => metric_2.duration + metric_3.duration,
    )

    expect(sidekiq_job_count.data).to eq(
      { job_name: "Bob", success: false } => 2,
      { job_name: "Bob", success: true } => 1,
    )
  end

  it "handles scheduled job metrics" do
    metric_1 = DiscoursePrometheus::InternalMetric::Job.new
    metric_1.scheduled = true
    metric_1.job_name = "Bob"
    metric_1.duration = 1.778
    metric_1.success = true
    metric_1.count = 1
    collector.process(metric_1.to_json)

    metric_2 = DiscoursePrometheus::InternalMetric::Job.new
    metric_2.scheduled = true
    metric_2.job_name = "Bob"
    metric_2.duration = 1.123123
    metric_2.success = false
    metric_2.count = 1
    collector.process(metric_2.to_json)

    metrics = collector.prometheus_metrics

    duration = metrics.find { |m| m.name == "scheduled_job_duration_seconds" }
    count = metrics.find { |m| m.name == "scheduled_job_count" }

    expect(duration.data).to eq(
      { job_name: "Bob", success: true } => metric_1.duration,
      { job_name: "Bob", success: false } => metric_2.duration,
    )

    expect(count.data).to eq(
      { job_name: "Bob", success: true } => 1,
      { job_name: "Bob", success: false } => 1,
    )
  end

  it "handles job initialization metrics" do
    metric = DiscoursePrometheus::InternalMetric::Job.new

    metric.scheduled = true
    metric.job_name = "Bob"
    metric.count = 0
    metric.duration = 0
    metric.success = true

    collector.process(metric.to_json)
    metrics = collector.prometheus_metrics

    duration = metrics.find { |m| m.name == "scheduled_job_duration_seconds" }
    count = metrics.find { |m| m.name == "scheduled_job_count" }

    expect(duration.data).to eq({ job_name: "Bob", success: true } => 0)
    expect(count.data).to eq({ job_name: "Bob", success: true } => 0)
  end

  it "handles process metrics" do
    skip("skipped because /proc does not exist on macOS") if RbConfig::CONFIG["arch"] =~ /darwin/

    reporter = DiscoursePrometheus::Reporter::Process.new(:web)
    collector.process(reporter.collect.to_json)

    metrics = collector.prometheus_metrics
    rss = metrics.find { |m| m.name == "rss" }

    expect(rss.data[type: "web", pid: Process.pid]).to be > 0

    ar = metrics.find { |metric| metric.name == "active_record_connections_count" }

    expect(ar.data[type: "web", pid: Process.pid, status: "busy"]).to be > 0
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

      metric = DiscoursePrometheus::Reporter::Process.new(:web).collect

      collector.process(metric.to_json)

      metric = collector.prometheus_metrics.find { |m| m.name == "job_failures" }

      expect(metric.data).to eq(
        {
          {
            "family" => "scheduled",
            :type => "web",
            :pid => Process.pid,
            "job" => "Jobs::ReindexSearch",
          } =>
            2,
        },
      )
    end
  end

  it "expires old metrics" do
    old_metric = DiscoursePrometheus::InternalMetric::Process.new
    old_metric.pid = 100
    old_metric.rss = 100
    old_metric.major_gc_count = old_metric.minor_gc_count = old_metric.total_allocated_objects = 0

    collector.process(old_metric.to_json)

    # travel forward in time
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    later = now + 61
    Process.stubs(:clock_gettime).returns(later)

    new_metric = DiscoursePrometheus::InternalMetric::Process.new
    new_metric.pid = 200
    new_metric.rss = 20
    new_metric.major_gc_count = new_metric.minor_gc_count = new_metric.total_allocated_objects = 0

    collector.process(new_metric.to_json)

    metrics = collector.prometheus_metrics
    rss = metrics.find { |m| m.name == "rss" }

    expect(rss.data[type: nil, pid: 200]).to be > 0
    expect(rss.data.length).to eq(1)
  end

  it "counts metrics correctly" do
    metrics = []
    metrics << DiscoursePrometheus::InternalMetric::Web.get(
      tracked: true,
      verb: "GET",
      status_code: 200,
      db: "bob",
    )
    metrics << DiscoursePrometheus::InternalMetric::Web.get(
      tracked: true,
      verb: "GET",
      status_code: 200,
      db: "bob",
    )
    metrics << DiscoursePrometheus::InternalMetric::Web.get(
      tracked: true,
      verb: "GET",
      logged_in: true,
      status_code: 200,
      db: "bill",
    )
    metrics << DiscoursePrometheus::InternalMetric::Web.get(
      tracked: true,
      verb: "GET",
      mobile: true,
      status_code: 200,
      db: "jake",
    )
    metrics << DiscoursePrometheus::InternalMetric::Web.get(
      tracked: false,
      verb: "GET",
      status_code: 200,
      db: "bob",
      user_api: true,
    )
    metrics << DiscoursePrometheus::InternalMetric::Web.get(
      tracked: false,
      verb: "GET",
      status_code: 300,
      db: "bob",
      admin_api: true,
    )
    metrics << DiscoursePrometheus::InternalMetric::Web.get(
      tracked: false,
      verb: "GET",
      background: true,
      status_code: 418,
      db: "bob",
    )
    metrics << DiscoursePrometheus::InternalMetric::Web.get(
      tracked: false,
      verb: "GET",
      background: true,
      status_code: 200,
      db: "bob",
    )

    metrics.each { |metric| collector.process(metric.to_json) }

    exported = collector.prometheus_metrics

    page_views = exported.find { |m| m.name == "page_views" }

    expected = {
      { db: "bob", type: "anon", device: "desktop" } => 2,
      { db: "bill", type: "logged_in", device: "desktop" } => 1,
      { db: "jake", type: "anon", device: "mobile" } => 1,
    }

    expect(page_views.data).to eq(expected)

    http_requests = exported.find { |m| m.name == "http_requests" }
    expected = {
      { db: "bob", api: "web", verb: "GET", type: "regular", status: 200 } => 2,
      { db: "bill", api: "web", verb: "GET", type: "regular", status: 200 } => 1,
      { db: "jake", api: "web", verb: "GET", type: "regular", status: 200 } => 1,
      { db: "bob", api: "user", verb: "GET", type: "regular", status: 200 } => 1,
      { db: "bob", api: "admin", verb: "GET", type: "regular", status: 300 } => 1,
      { db: "bob", api: "web", verb: "GET", type: "background", status: "-1" } => 1,
      { db: "bob", api: "web", verb: "GET", type: "background", status: 200 } => 1,
    }
    expect(http_requests.data).to eq(expected)
  end

  it "processes timing attributes in web metrics correctly" do
    metrics = []

    metrics << DiscoursePrometheus::InternalMetric::Web.get(
      status_code: 200,
      duration: 14,
      sql_duration: 1,
      redis_duration: 2,
      net_duration: 3,
      gc_duration: 4,
      gc_major_count: 5,
      gc_minor_count: 6,
      queue_duration: 7,
      json: true,
      controller: "list",
      action: "latest",
      logged_in: true,
    )

    metrics << DiscoursePrometheus::InternalMetric::Web.get(
      status_code: 302,
      duration: 14,
      sql_duration: 1,
      redis_duration: 2,
      net_duration: 3,
      gc_duration: 4,
      gc_major_count: 5,
      gc_minor_count: 6,
      queue_duration: 7,
      controller: "list",
      action: "latest",
      logged_in: false,
      html: true,
    )

    metrics.each { |metric| collector.process(metric.to_json) }

    exported = collector.prometheus_metrics

    assert_metric = ->(metric_name, sum, metric_type) do
      metric = exported.find { |m| m.name == metric_name }

      expect(metric.type).to eq(metric_type)

      expect(metric.to_h).to eq(
        {
          controller: "list",
          action: "latest",
          success: true,
          logged_in: true,
          content_type: "json",
        } => {
          "count" => 1,
          "sum" => sum,
        },
        {
          controller: "list",
          action: "latest",
          success: false,
          logged_in: false,
          content_type: "html",
        } => {
          "count" => 1,
          "sum" => sum,
        },
      )
    end

    [
      ["http_duration_seconds", 14.0, "summary"],
      ["http_application_duration_seconds", 4.0, "summary"],
      ["http_sql_duration_seconds", 1.0, "summary"],
      ["http_redis_duration_seconds", 2.0, "summary"],
      ["http_net_duration_seconds", 3.0, "summary"],
      ["http_gc_duration_seconds", 4.0, "summary"],
      ["http_requests_duration_seconds", 14.0, "histogram"],
      ["http_requests_application_duration_seconds", 4.0, "histogram"],
      ["http_requests_sql_duration_seconds", 1.0, "histogram"],
      ["http_requests_redis_duration_seconds", 2.0, "histogram"],
      ["http_requests_net_duration_seconds", 3.0, "histogram"],
      ["http_requests_gc_duration_seconds", 4.0, "histogram"],
    ].each { |args| assert_metric.call(*args) }

    expect(
      exported.find { |metric| metric.name == "http_requests_queue_duration_seconds" }.to_h,
    ).to eq({} => { "count" => 2, "sum" => 14.0 })

    expect(exported.find { |metric| metric.name == "http_gc_major_count" }.to_h).to eq(
      {
        controller: "list",
        action: "latest",
        success: true,
        logged_in: true,
        content_type: "json",
      } =>
        5,
      {
        controller: "list",
        action: "latest",
        success: false,
        logged_in: false,
        content_type: "html",
      } =>
        5,
    )

    expect(exported.find { |metric| metric.name == "http_gc_minor_count" }.to_h).to eq(
      {
        controller: "list",
        action: "latest",
        success: true,
        logged_in: true,
        content_type: "json",
      } =>
        6,
      {
        controller: "list",
        action: "latest",
        success: false,
        logged_in: false,
        content_type: "html",
      } =>
        6,
    )
  end
end
