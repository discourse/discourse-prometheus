# frozen_string_literal: true

module DiscoursePrometheus::InternalMetric
  class Web

    FLOAT_ATTRS = %w{
      duration
      sql_duration
      redis_duration
    }

    INT_ATTRS = %w{
      sql_calls
      redis_calls
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
    }

    STRING_ATTRS = %w{
      controller
      action
      host
      db
    }

    (FLOAT_ATTRS + INT_ATTRS + BOOL_ATTRS + STRING_ATTRS).each do |attr|
      attr_accessor attr
    end

    # optimized to keep collecting as cheap as possible
    class_eval <<~RUBY
      def to_s
        str = String.new
        #{FLOAT_ATTRS.map { |f| "str << #{f}.to_f.round(4).to_s" }.join("\nstr << \" \"\n")}
        str << " "
        #{INT_ATTRS.map { |f| "str << #{f}.to_i.to_s" }.join("\nstr << \" \"\n")}
        str << " "
        #{BOOL_ATTRS.map { |f| "str << (#{f} || false ? 't' : 'f')" }.join("\nstr << \" \"\n")}
        str << " "
        #{STRING_ATTRS.map { |f| "str << #{f}.to_s" }.join("\nstr << \" \"\n")}
      end
    RUBY

    # for debugging
    def to_h
      h = {}
      FLOAT_ATTRS.each { |f| h[f] = send f }
      INT_ATTRS.each { |i| h[i] = send i }
      BOOL_ATTRS.each { |b| h[b] = send b }
      STRING_ATTRS.each { |s| h[s] = send s }
      h
    end

    def self.get(hash)
      metric = new
      hash.each do |k, v|
        metric.send "#{k}=", v
      end
      metric
    end

    def self.parse(str)
      result = self.new

      split = str.split(/[ ]/)

      i = 0

      FLOAT_ATTRS.each do |attr|
        result.send "#{attr}=", split[i].to_f
        i += 1
      end

      INT_ATTRS.each do |attr|
        result.send "#{attr}=", split[i].to_i
        i += 1
      end

      BOOL_ATTRS.each do |attr|
        result.send "#{attr}=", split[i] == 't'
        i += 1
      end

      STRING_ATTRS.each do |attr|
        result.send "#{attr}=", split[i].to_s
        i += 1
      end
      result
    end

    def self.multisite?
      @multisite ||= (
        File.exists?(RailsMultisite::ConnectionManagement.config_filename) ? :true : :false
      ) == :true
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
