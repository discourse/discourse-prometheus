require 'rails_helper'

module DiscoursePrometheus::InternalMetric
  describe Custom do
    let(:result_hash) do
      {
        name: "post_count",
        labels: nil,
        description: "Total number of posts",
        type: "Gauge",
        value: 120,
        _type: "Custom"
      }
    end

    it "creates hash for Custom metric" do
      metric = Custom.new
      metric.name = "post_count"
      metric.description = "Total number of posts"
      metric.type = "Gauge"
      metric.value = 120

      expect(metric.to_h).to eq(result_hash)
    end

    it "creates hash for Custom gauge type metric using class method" do
      hash = Custom.create_gauge_hash("post_count", "Total number of posts", 120)
      expect(hash).to eq(result_hash)
    end
  end
end
