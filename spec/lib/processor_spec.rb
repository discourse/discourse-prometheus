require 'rails_helper'

module DiscoursePrometheus
  describe Processor do

    it "Can pass in via a pipe" do

      pipe = BigPipe.new(3)
      metric = Metric.get(tracked: true, status_code: 200, host: "bob")
      pipe << metric.to_s

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
