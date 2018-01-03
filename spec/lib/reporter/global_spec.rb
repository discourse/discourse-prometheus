require 'rails_helper'

module DiscoursePrometheus
  describe Reporter::Global do
    def check_for(metric, *args)
      args.each do |arg|
        expect(metric.send arg).to be > 0
      end
    end

    it "Can collect gc stats" do

      collector = Reporter::Global.new(recycle_every: 2)
      metric = collector.collect

      expect(metric.redis_slave_available).to eq(0)

      id = metric.object_id

      # test recycling
      expect(collector.collect.object_id).to eq(id)
      expect(collector.collect.object_id).not_to eq(id)
    end
  end
end
