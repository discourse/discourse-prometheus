# frozen_string_literal: true

require 'rails_helper'

module DiscoursePrometheus::InternalMetric
  describe Web do
    it "Can round trip host" do
      metric = Web.get(tracked: true, status_code: 200, host: "bob")
      metric = Base.from_h(metric.to_h)
      expect(metric.host).to eq("bob")
    end

    it "Can round trip to a hash" do
      metric = Web.new

      metric.duration = 0.00074
      metric.sql_duration = 0.00015
      metric.redis_duration = 0.00014

      metric.redis_calls = 2
      metric.sql_calls = 3

      metric.controller = "controller"
      metric.action = "action"

      metric.crawler = true

      metric = Base.from_h(metric.to_h)

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
      it "Can get controller/action" do
        env = {
          "action_dispatch.request.parameters" => { "controller" => 'con', "action" => 'act' }
        }

        metric = Web.from_env_data(env, {}, "")

        expect(metric.controller).to eq('con')
        expect(metric.action).to eq('act')
      end

      it "Can fish out logged data from discourse" do
        data = {
          status: 201,
          is_crawler: false,
          has_auth_cookie: true,
          is_background: nil,
          is_mobile: true,
          track_view: true
        }

        metric = Web.from_env_data({}, data, "test")

        expect(metric.status_code).to eq(201)
        expect(metric.crawler).to eq(false)
        expect(metric.logged_in).to eq(true)
        expect(metric.background).to eq(false)
        expect(metric.mobile).to eq(true)
        expect(metric.tracked).to eq(true)
        expect(metric.host).to eq("test")
      end

      it "Can figure out if it is an ajax call" do
        env = {
          "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest"
        }

        metric = Web.from_env_data(env, {}, "")

        expect(metric.ajax).to eq(true)
      end

      it "Can detect json requests" do
        env = {
          "PATH_INFO" => "/test.json"
        }

        metric = Web.from_env_data(env, {}, "")

        expect(metric.json).to eq(true)
      end

      it "Can detect json requests from header" do
        env = {
          "HTTP_ACCEPT" => "application/json, text/javascript, */*; q=0.01"
        }

        metric = Web.from_env_data(env, {}, "")

        expect(metric.json).to eq(true)
      end

      it "Can detect request method" do
        env = {
          "REQUEST_METHOD" => "GET"
        }

        metric = Web.from_env_data(env, {}, "")

        expect(metric.verb).to eq("GET")

        env = {
          "REQUEST_METHOD" => "TEST"
        }

        metric = Web.from_env_data(env, {}, "")

        expect(metric.verb).to eq("OTHER")
      end

      it "Can fish out timings if available" do
        data = {
          timing: {
            total_duration: 0.1,
            sql: { duration: 0.2, calls: 5 },
            redis: { duration: 0.3, calls: 6 }
          }
        }

        metric = Web.from_env_data({}, data, "")

        expect(metric.duration).to eq(0.1)
        expect(metric.sql_duration).to eq(0.2)
        expect(metric.redis_duration).to eq(0.3)

        expect(metric.sql_calls).to eq(5)
        expect(metric.redis_calls).to eq(6)
      end
    end
  end
end
