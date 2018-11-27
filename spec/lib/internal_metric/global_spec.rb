require 'rails_helper'

module DiscoursePrometheus::InternalMetric
  describe Global do
    it "can collect global metrics" do
      metric = Global.new
      metric.collect

      expect(metric.sidekiq_processes).not_to eq(nil)
      expect(metric.postgres_master_available).to eq(1)
      expect(metric.postgres_replica_available).to eq(0)
    end

    describe 'when a replica has been configured' do
      before do
        @orig_logger = Rails.logger
        Rails.logger = @fake_logger = FakeLogger.new

        config = ActiveRecord::Base.connection_config

        config.merge!(
          replica_host: 'localhost',
          replica_port: 1111
        )
      end

      after do
        Rails.logger = @orig_logger
      end

      it 'should collect the right metrics' do
        metric = Global.new
        metric.collect

        expect(metric.postgres_master_available).to eq(1)
        expect(metric.postgres_replica_available).to eq(0)
        expect(@fake_logger.errors.first).to match(/Connection refused/)
      end
    end
  end
end
