require 'rails_helper'

module DiscoursePrometheus::InternalMetric
  describe Global do
    it "can collect global metrics" do
      metric = Global.new
      metric.collect

      expect(metric.sidekiq_processes).not_to eq(nil)
    end
  end
end
