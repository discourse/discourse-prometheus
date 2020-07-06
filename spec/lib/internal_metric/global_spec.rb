# frozen_string_literal: true

require 'rails_helper'

module DiscoursePrometheus::InternalMetric
  describe Global do
    let(:db) { RailsMultisite::ConnectionManagement.current_db }
    let(:metric) { Global.new }

    after do
      metric.reset!
    end

    it "can collect global metrics" do
      metric.collect

      expect(metric.sidekiq_processes).not_to eq(nil)
      expect(metric.postgres_master_available).to eq(1)
      expect(metric.postgres_replica_available).to eq(nil)
    end

    it "should collect the missing upload metrics" do
      Discourse.stats.set("missing_s3_uploads", 2)

      metric.collect

      expect(metric.missing_s3_uploads).to eq(
        { db: db } => 2
      )
    end

    it 'should throttle the collection of missing upload metrics' do
      Discourse.stats.set("missing_s3_uploads", 2)

      metric.collect

      expect(metric.missing_s3_uploads).to eq(
        { db: db } => 2
      )

      Discourse.stats.set("missing_s3_uploads", 0)
      metric.collect

      expect(metric.missing_s3_uploads).to eq(
        { db: db } => 2
      )

      metric.reset!
      metric.collect

      expect(metric.missing_s3_uploads).to eq(
        { db: db } => 0
      )
    end

    describe 'sidekiq paused' do
      after do
        Sidekiq.unpause_all!
      end

      it "should collect the right metrics" do
        metric.collect

        expect(metric.sidekiq_paused).to eq(
          { db: db } => nil
        )

        Sidekiq.pause!
        metric.collect

        expect(metric.sidekiq_paused).to eq(
          { db: db } => 1
        )
      end
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
        metric.collect

        expect(metric.postgres_master_available).to eq(1)
        expect(metric.postgres_replica_available).to eq(0)
      end
    end
  end
end
