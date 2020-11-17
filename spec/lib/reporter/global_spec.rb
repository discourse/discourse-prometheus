# frozen_string_literal: true

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
    ensure
      metric.reset!
    end

    describe "with readonly mode cleanup" do
      after do
        Discourse.disable_readonly_mode(Discourse::PG_FORCE_READONLY_MODE_KEY)
        Discourse.clear_readonly!
      end

      it "can collect readonly data from the redis keys" do
        metric = Reporter::Global.new.collect

        Discourse::READONLY_KEYS.each do |k|
          expect(metric.readonly_sites[key: k]).to eq(0)
        end

        Discourse.enable_readonly_mode(Discourse::PG_FORCE_READONLY_MODE_KEY)

        metric = Reporter::Global.new.collect
        Discourse::READONLY_KEYS.each do |k|
          expect(metric.readonly_sites[key: k]).to eq(k == Discourse::PG_FORCE_READONLY_MODE_KEY ? 1 : 0)
        end
      end
    end
  end
end
