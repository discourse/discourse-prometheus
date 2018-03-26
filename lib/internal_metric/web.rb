# frozen_string_literal: true

module DiscoursePrometheus::InternalMetric
  class Web < Base

    FLOAT_ATTRS = %w{
      duration
      sql_duration
      net_duration
      redis_duration
      queue_duration
    }

    INT_ATTRS = %w{
      sql_calls
      redis_calls
      net_calls
      status_code
    }

    BOOL_ATTRS = %w{
      ajax
      background
      logged_in
      crawler
      mobile
      tracked
      json
      admin_api
      user_api
    }

    STRING_ATTRS = %w{
      controller
      action
      host
      db
    }

    (FLOAT_ATTRS + INT_ATTRS + BOOL_ATTRS + STRING_ATTRS).each do |attr|
      attribute attr
    end

    def self.get(hash)
      metric = new
      hash.each do |k, v|
        metric.send "#{k}=", v
      end
      metric
    end

    def self.multisite?
      @multisite ||= Rails.configuration.multisite
    end

    def self.from_env_data(env, data, host)
      metric = self.new

      data ||= {}

      if multisite?
        spec = RailsMultisite::ConnectionManagement.connection_spec(host: host)
        if spec
          metric.db = spec.config[:database]
        end
      else
        metric.db = nil
      end

      if queue_start = env['HTTP_X_REQUEST_START']
        queue_start = queue_start.split("t=")[1].to_f
        metric.queue_duration = (Time.now.to_f - queue_start) / 1000.0
      else
        metric.queue_duration = 0.0
      end

      metric.admin_api = !!env['_DISCOURSE_API']
      metric.user_api = !!env['_DISCOURSE_USER_API']

      if ad_params = env['action_dispatch.request.parameters']
        metric.controller = ad_params['controller']
        metric.action = ad_params['action']
      end

      if timing = data[:timing]
        metric.duration = timing[:total_duration]

        if sql = timing[:sql]
          metric.sql_duration = sql[:duration]
          metric.sql_calls = sql[:calls]
        end

        if redis = timing[:redis]
          metric.redis_duration = redis[:duration]
          metric.redis_calls = redis[:calls]
        end

        if net = timing[:net]
          metric.net_duration = net[:duration]
          metric.net_calls = net[:calls]
        end
      end

      metric.status_code = data[:status].to_i
      metric.crawler = !!data[:is_crawler]
      metric.logged_in = !!data[:has_auth_cookie]
      metric.background = !!data[:is_background]
      metric.mobile = !!data[:is_mobile]
      metric.tracked = !!data[:track_view]
      metric.host = host

      metric.json = env["PATH_INFO"].to_s.ends_with?(".json") ||
        env["HTTP_ACCEPT"].to_s.include?("application/json")

      metric.ajax = env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
      metric
    end
  end
end
