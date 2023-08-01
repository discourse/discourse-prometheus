# frozen_string_literal: true

module DiscoursePrometheus::InternalMetric
  class Web < Base
    FLOAT_ATTRS = %w[duration sql_duration net_duration redis_duration queue_duration gc_duration]

    INT_ATTRS = %w[sql_calls redis_calls net_calls status_code gc_major_count gc_minor_count]

    BOOL_ATTRS = %w[
      ajax
      background
      logged_in
      crawler
      mobile
      tracked
      json
      html
      admin_api
      user_api
      forced_anon
    ]

    STRING_ATTRS = %w[background_type verb controller action host db cache]

    (FLOAT_ATTRS + INT_ATTRS + BOOL_ATTRS + STRING_ATTRS).each { |attr| attribute attr }

    ALLOWED_REQUEST_METHODS = Set["HEAD", "GET", "PUT", "POST", "DELETE"]

    def self.get(hash)
      metric = new
      hash.each { |k, v| metric.send "#{k}=", v }
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
        metric.db = spec.config[:database] if spec
      else
        metric.db = nil
      end

      if queue_seconds = data[:queue_seconds]
        metric.queue_duration = queue_seconds
      else
        metric.queue_duration = 0.0
      end

      metric.admin_api = !!env["_DISCOURSE_API"]
      metric.user_api = !!env["_DISCOURSE_USER_API"]

      metric.verb = env["REQUEST_METHOD"]
      metric.verb = "OTHER" if !ALLOWED_REQUEST_METHODS.include?(metric.verb)

      if ad_params = env["action_dispatch.request.parameters"]
        metric.controller = ad_params["controller"]
        metric.action = ad_params["action"]
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

        if gc = timing[:gc]
          metric.gc_duration = gc[:time]
          metric.gc_major_count = gc[:major_count]
          metric.gc_minor_count = gc[:minor_count]
        end
      end

      metric.status_code = data[:status].to_i
      metric.crawler = !!data[:is_crawler]
      metric.logged_in = !!data[:has_auth_cookie]
      metric.background = !!data[:is_background]
      metric.background_type = data[:background_type]
      metric.mobile = !!data[:is_mobile]
      metric.tracked = !!data[:track_view]
      metric.cache = data[:cache]
      metric.host = host

      metric.json =
        env["PATH_INFO"].to_s.ends_with?(".json") ||
          env["HTTP_ACCEPT"].to_s.include?("application/json")

      metric.html =
        env["PATH_INFO"].to_s.ends_with?(".html") || env["HTTP_ACCEPT"].to_s.include?("text/html")

      metric.ajax = env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
      metric.forced_anon = !!env["DISCOURSE_FORCE_ANON"]

      metric
    end
  end
end
