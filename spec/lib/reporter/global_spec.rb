# frozen_string_literal: true

require "rails_helper"
require_relative "../../support/null_metric"

module DiscoursePrometheus
  describe Reporter::Global do
    def check_for(metric, *args)
      args.each { |arg| expect(metric.send arg).to be > 0 }
    end

    it "Can collect gc stats" do
      collector = Reporter::Global.new(recycle_every: 2)
      metric = collector.collect.first

      expect(metric.redis_slave_available[{ type: "main" }]).to eq(0)

      id = metric.object_id

      # test recycling
      expect(collector.collect.first.object_id).to eq(id)
      expect(collector.collect.first.object_id).not_to eq(id)
    ensure
      metric.reset!
    end

    describe "with readonly mode cleanup" do
      after do
        Discourse.disable_readonly_mode(Discourse::PG_FORCE_READONLY_MODE_KEY)
        Discourse.clear_readonly!
      end

      it "can collect readonly data from the redis keys" do
        metric = Reporter::Global.new.collect.first

        Discourse::READONLY_KEYS.each { |k| expect(metric.readonly_sites[key: k]).to eq(0) }

        Discourse.enable_readonly_mode(Discourse::PG_FORCE_READONLY_MODE_KEY)

        metric = Reporter::Global.new.collect.first
        Discourse::READONLY_KEYS.each do |k|
          expect(metric.readonly_sites[key: k]).to eq(
            k == Discourse::PG_FORCE_READONLY_MODE_KEY ? 1 : 0,
          )
        end
      ensure
        metric.reset!
      end
    end

    describe "adding custom collectors" do
      after { DiscoursePluginRegistry.reset_register!(:global_collectors) }

      it "collects custom metrics added to the global_collectors registry" do
        null_metric_klass = DiscoursePrometheus::NullMetric
        DiscoursePluginRegistry.register_global_collector(null_metric_klass, Plugin::Instance.new)

        metric = Reporter::Global.new.collect.last

        expect(metric.name).to eq(null_metric_klass.new.name)
      end
    end
  end
end
