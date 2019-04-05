require 'rails_helper'

module DiscoursePrometheus::InternalMetric
  describe Custom do
    it "creates hash for Custom metric" do
      metric = Custom.new
      metric.name = "post_count"
      metric.description = "Total number of posts"
      metric.type = "Guage"
      metric.value = 120

      expect(metric.to_h).to eq(
        name: "post_count",
        labels: nil,
        description: "Total number of posts",
        type: "Guage",
        value: 120,
        _type: "Custom"
      )
    end
  end
end
