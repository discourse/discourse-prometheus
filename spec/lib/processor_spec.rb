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
          host: "",
          type: "anon",
          device: "desktop"
        } => 1
      }
      expect(page_views.data).to eq(expected)

    end

    it "Can count metrics correctly" do
      metrics = []
      metrics << Metric.get(tracked: true, status_code: 200, host: "bob")
      metrics << Metric.get(tracked: true, status_code: 200, host: "bob")
      metrics << Metric.get(tracked: true, logged_in: true, status_code: 200, host: "bill")
      metrics << Metric.get(tracked: true, mobile: true, status_code: 200, host: "jake")
      metrics << Metric.get(tracked: false, status_code: 200, host: "bob")
      metrics << Metric.get(tracked: false, status_code: 300, host: "bob")
      metrics << Metric.get(tracked: false, background: true, status_code: 300, host: "bob")

      processed = Processor.process(metrics.each)

      page_views = processed.find { |m| m.name == "page_views" }

      expected = {
        { host: "bob", type: "anon", device: "desktop" } => 2,
        { host: "bill", type: "logged_in", device: "desktop" } => 1,
        { host: "jake", type: "anon", device: "mobile" } => 1
      }

      expect(page_views.data).to eq(expected)

      http_requests = processed.find { |m| m.name == "http_requests" }
      expected = {
        { host: "bob", status: 200 } => 3,
        { host: "bill", status: 200 } => 1,
        { host: "jake", status: 200 } => 1,
        { host: "bob", status: 300 } => 1,
        { host: "bob", type: "background" } => 1
      }
      expect(http_requests.data).to eq(expected)
    end
  end
end
