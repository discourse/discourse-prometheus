# frozen_string_literal: true

RSpec.describe DiscoursePrometheus::InternalMetric::Web do
  it "round trips host" do
    metric = described_class.get(tracked: true, status_code: 200, host: "bob")
    metric = DiscoursePrometheus::InternalMetric::Base.from_h(metric.to_h)
    expect(metric.host).to eq("bob")
  end

  it "round trips to a hash" do
    metric = described_class.new

    metric.duration = 0.00074
    metric.sql_duration = 0.00015
    metric.redis_duration = 0.00014

    metric.redis_calls = 2
    metric.sql_calls = 3

    metric.controller = "controller"
    metric.action = "action"

    metric.crawler = true

    metric = DiscoursePrometheus::InternalMetric::Base.from_h(metric.to_h)

    expect(metric.duration).to eq(0.00074)
    expect(metric.sql_duration).to eq(0.00015)
    expect(metric.redis_duration).to eq(0.00014)

    expect(metric.redis_calls).to eq(2)
    expect(metric.sql_calls).to eq(3)

    expect(metric.controller).to eq("controller")
    expect(metric.action).to eq("action")

    expect(metric.crawler).to eq(true)
    expect(metric.tracked).to eq(nil)
  end

  describe "from_env_data" do
    it "gets controller/action" do
      env = { "action_dispatch.request.parameters" => { "controller" => "con", "action" => "act" } }

      metric = described_class.from_env_data(env, {}, "")

      expect(metric.controller).to eq("con")
      expect(metric.action).to eq("act")
    end

    it "fishes out logged data from discourse" do
      data = {
        status: 201,
        is_crawler: false,
        has_auth_cookie: true,
        is_background: nil,
        is_mobile: true,
        track_view: true,
      }

      metric = described_class.from_env_data({}, data, "test")

      expect(metric.status_code).to eq(201)
      expect(metric.crawler).to eq(false)
      expect(metric.logged_in).to eq(true)
      expect(metric.background).to eq(false)
      expect(metric.mobile).to eq(true)
      expect(metric.tracked).to eq(true)
      expect(metric.host).to eq("test")
    end

    it "figures out if it is an ajax call" do
      env = { "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest" }

      metric = described_class.from_env_data(env, {}, "")

      expect(metric.ajax).to eq(true)
    end

    it "detects json requests" do
      env = { "PATH_INFO" => "/test.json" }

      metric = described_class.from_env_data(env, {}, "")

      expect(metric.json).to eq(true)
    end

    it "detects json requests from header" do
      env = { "HTTP_ACCEPT" => "application/json, text/javascript, */*; q=0.01" }

      metric = described_class.from_env_data(env, {}, "")

      expect(metric.json).to eq(true)
    end

    it "detects request method" do
      env = { "REQUEST_METHOD" => "GET" }

      metric = described_class.from_env_data(env, {}, "")

      expect(metric.verb).to eq("GET")

      env = { "REQUEST_METHOD" => "TEST" }

      metric = described_class.from_env_data(env, {}, "")

      expect(metric.verb).to eq("OTHER")
    end

    it "fishes out timings if available" do
      data = {
        timing: {
          total_duration: 0.1,
          sql: {
            duration: 0.2,
            calls: 5,
          },
          redis: {
            duration: 0.3,
            calls: 6,
          },
          gc: {
            time: 0.4,
            major_count: 7,
            minor_count: 8,
          },
        },
      }

      metric = described_class.from_env_data({}, data, "")

      expect(metric.duration).to eq(0.1)
      expect(metric.sql_duration).to eq(0.2)
      expect(metric.redis_duration).to eq(0.3)

      expect(metric.sql_calls).to eq(5)
      expect(metric.redis_calls).to eq(6)

      expect(metric.gc_duration).to eq(0.4)
      expect(metric.gc_major_count).to eq(7)
      expect(metric.gc_minor_count).to eq(8)
    end
  end
end
