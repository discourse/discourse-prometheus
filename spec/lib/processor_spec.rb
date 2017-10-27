require 'rails_helper'

module DiscoursePrometheus
  describe Processor do

    it "Can handle scheduled job metrics" do
      processor = Processor.new
      metric = JobMetric.new

      metric.scheduled = true
      metric.job_name = "Bob"
      metric.duration = 1.778

      processor.process(metric)
      metrics = processor.prometheus_metrics

      duration = metrics.find { |m| m.name == "scheduled_job_duration_seconds" }
      count = metrics.find { |m| m.name == "scheduled_job_count" }

      expect(duration.data).to eq({ job_name: "Bob" } => 1.778)
      expect(count.data).to eq({ job_name: "Bob" } => 1)
    end

    it "Can handle process metrics" do
      processor = Processor.new
      collector = ProcessCollector.new(:web)
      processor.process(collector.collect)

      metrics = processor.prometheus_metrics
      rss = metrics.find { |m| m.name == "rss" }

      expect(rss.data[type: :web, pid: Process.pid]).to be > 0
    end

    it "Can pass in via a pipe" do

      pipe = BigPipe.new(3)
      metric = Metric.get(tracked: true, status_code: 200, host: "bob")
      pipe << metric
      pipe.flush

      metrics = Processor.process(pipe.process)

      page_views = metrics.find { |m| m.name == "page_views" }
      expected = {
        {
          type: "anon",
          device: "desktop",
          db: "default"
        } => 1
      }
      expect(page_views.data).to eq(expected)

    end

    it "Can count metrics correctly" do
      metrics = []
      metrics << Metric.get(tracked: true, status_code: 200, db: "bob")
      metrics << Metric.get(tracked: true, status_code: 200, db: "bob")
      metrics << Metric.get(tracked: true, logged_in: true, status_code: 200, db: "bill")
      metrics << Metric.get(tracked: true, mobile: true, status_code: 200, db: "jake")
      metrics << Metric.get(tracked: false, status_code: 200, db: "bob")
      metrics << Metric.get(tracked: false, status_code: 300, db: "bob")
      metrics << Metric.get(tracked: false, background: true, status_code: 300, db: "bob")

      processed = Processor.process(metrics.each)

      page_views = processed.find { |m| m.name == "page_views" }

      expected = {
        { db: "bob", type: "anon", device: "desktop" } => 2,
        { db: "bill", type: "logged_in", device: "desktop" } => 1,
        { db: "jake", type: "anon", device: "mobile" } => 1
      }

      expect(page_views.data).to eq(expected)

      http_requests = processed.find { |m| m.name == "http_requests" }
      expected = {
        { db: "bob", status: 200, type: "regular" } => 3,
        { db: "bill", status: 200, type: "regular" } => 1,
        { db: "jake", status: 200, type: "regular" } => 1,
        { db: "bob", status: 300, type: "regular" } => 1,
        { db: "bob", status: "-1", type: "background" } => 1
      }
      expect(http_requests.data).to eq(expected)
    end
  end
end
