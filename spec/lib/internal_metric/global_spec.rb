# frozen_string_literal: true

RSpec.describe DiscoursePrometheus::InternalMetric::Global do
  let(:db) { RailsMultisite::ConnectionManagement.current_db }
  let(:metric) { described_class.new }

  after { metric.reset! }

  it "collects global metrics" do
    metric.collect

    expect(metric.sidekiq_processes).not_to eq(nil)
    expect(metric.postgres_master_available).to eq(1)
    expect(metric.postgres_replica_available).to eq(nil)
    expect(metric.redis_primary_available).to eq({ { type: "main" } => 1 })
    expect(metric.redis_replica_available).to eq({ { type: "main" } => 0 })
  end

  it "collects the version_info metric" do
    metric.collect

    expect(metric.version_info.count).to eq(1)
    labels = metric.version_info.keys.first
    value = metric.version_info.values.first

    expect(labels[:revision]).to match(/\A[0-9a-f]{40}\z/)
    expect(labels[:version]).to eq(Discourse::VERSION::STRING)
    expect(value).to eq(1)
  end

  if SiteSetting.respond_to?("s3_inventory_bucket")
    describe "missing_s3_uploads metric" do
      before { SiteSetting.s3_inventory_bucket = "some-bucket/some/prefix" }

      it "collects the missing upload metrics" do
        Discourse.stats.set("missing_s3_uploads", 2)

        metric.collect

        expect(metric.missing_s3_uploads).to eq({ db: db } => 2)
      end

      it "throttles the collection of missing upload metrics" do
        Discourse.stats.set("missing_s3_uploads", 2)

        metric.collect

        expect(metric.missing_s3_uploads).to eq({ db: db } => 2)

        Discourse.stats.set("missing_s3_uploads", 0)
        metric.collect

        expect(metric.missing_s3_uploads).to eq({ db: db } => 2)

        metric.reset!
        metric.collect

        expect(metric.missing_s3_uploads).to eq({ db: db } => 0)
      end

      context "when `s3_inventory_bucket` has not been set for the site" do
        before { SiteSetting.s3_inventory_bucket = nil }

        it "does not expose the metric" do
          Discourse.stats.set("missing_s3_uploads", 2)

          metric.collect

          expect(metric.missing_s3_uploads).to eq({})
        end
      end
    end
  end

  describe "sidekiq paused" do
    after { Sidekiq.unpause_all! }

    it "collects the right metrics" do
      metric.collect

      expect(metric.sidekiq_paused).to eq({ db: db } => nil)

      Sidekiq.pause!
      metric.collect

      expect(metric.sidekiq_paused).to eq({ db: db } => 1)
    end
  end

  describe "when a replica has been configured" do
    before do
      config = ActiveRecord::Base.connection_db_config.configuration_hash.dup

      config.merge!(replica_host: "localhost", replica_port: 1111)
      ActiveRecord::Base.connection.disconnect!
      ActiveRecord::Base.establish_connection(config)
    end

    it "collects the right metrics" do
      metric.collect

      expect(metric.postgres_master_available).to eq(1)
      expect(metric.postgres_replica_available).to eq(0)
    end
  end

  it "collects postgres_highest_sequence metric" do
    Jobs::UpdateStats.new.execute

    metric.collect

    expect(metric.postgres_highest_sequence).to be_a_kind_of(Hash)
    expect(metric.postgres_highest_sequence[{ db: "default" }]).to be_present
  end
end
