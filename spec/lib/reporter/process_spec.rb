# frozen_string_literal: true

require 'rails_helper'

module DiscoursePrometheus
  describe Reporter::Process do
    def check_for(metric, *args)
      args.each do |arg|
        next if arg == :rss && RbConfig::CONFIG["arch"] =~ /darwin/ # macos does not support these metrics
        expect(metric.send arg).to be > 0
      end
    end

    it "Can collect gc stats" do
      ctx = MiniRacer::Context.new
      ctx.eval("")

      metric = Reporter::Process.new(:web).collect

      expect(metric.type).to eq('web')

      check_for(metric, :heap_live_slots, :heap_free_slots, :major_gc_count,
        :minor_gc_count, :total_allocated_objects, :v8_heap_size,
        :v8_heap_count, :v8_physical_size, :pid, :rss, :thread_count)
    end

    describe "with readonly mode cleanup" do
      after do
        Discourse.disable_readonly_mode(Discourse::PG_FORCE_READONLY_MODE_KEY)
        Discourse.clear_readonly!
      end

      it "can collect readonly data from the redis keys" do
        metric = Reporter::Process.new(:web).collect

        Discourse::READONLY_KEYS.each do |k|
          expect(metric.readonly_sites_count[key: k]).to eq(0)
        end

        Discourse.enable_readonly_mode(Discourse::PG_FORCE_READONLY_MODE_KEY)

        metric = Reporter::Process.new(:web).collect
        Discourse::READONLY_KEYS.each do |k|
          expect(metric.readonly_sites_count[key: k]).to eq(k == Discourse::PG_FORCE_READONLY_MODE_KEY ? 1 : 0)
        end
      end

      it "can collect recently readonly data" do
        freeze_time

        metric = Reporter::Process.new(:web).collect
        expect(metric.readonly_sites_count[{ key: 'redis_recently_readonly' }]).to eq(0)
        expect(metric.readonly_sites_count[{ key: 'postgres_recently_readonly' }]).to eq(0)

        Discourse.received_redis_readonly!

        metric = Reporter::Process.new(:web).collect
        expect(metric.readonly_sites_count[{ key: 'redis_recently_readonly' }]).to eq(1)
        expect(metric.readonly_sites_count[{ key: 'postgres_recently_readonly' }]).to eq(0)
      end
    end
  end
end
