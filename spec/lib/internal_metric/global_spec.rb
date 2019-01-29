require 'rails_helper'

module DiscoursePrometheus::InternalMetric
  describe Global do
    after do
      $redis.flushall
    end

    it "can collect global metrics" do
      metric = Global.new
      metric.collect

      expect(metric.sidekiq_processes).not_to eq(nil)
      expect(metric.sidekiq_paused).to eq(0)
      expect(metric.postgres_master_available).to eq(1)
      expect(metric.postgres_replica_available).to eq(nil)

      Sidekiq.pause!
      metric.collect

      expect(metric.sidekiq_paused).to eq(1)
    end

    describe 'when a replica has been configured' do
      before do
        config = ActiveRecord::Base.connection_config

        config.merge!(
          replica_host: 'localhost',
          replica_port: 1111
        )
      end

      it 'should collect the right metrics' do
        metric = Global.new
        metric.collect

        expect(metric.postgres_master_available).to eq(1)
        expect(metric.postgres_replica_available).to eq(0)
      end
    end
  end
end
