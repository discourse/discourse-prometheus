require 'rails_helper'

module DiscoursePrometheus
  describe GlobalMetric do
    it "can collect global metrics" do
      metric = GlobalMetric.new
      metric.collect

      expect(metric.sidekiq_processes).not_to eq(nil)
    end
  end
end
