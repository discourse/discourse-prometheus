# frozen_string_literal: true

require "ipaddr"

module DiscoursePrometheus
  module Middleware
  end
  class Middleware::Metrics
    def initialize(app, settings = {})
      @app = app
    end

    def call(env)
      intercept?(env) ? metrics(env) : @app.call(env)
    end

    private

    def is_private_ip?(env)
      request = Rack::Request.new(env)
      ip =
        begin
          IPAddr.new(request.ip)
        rescue StandardError
          nil
        end
      !!(ip && (ip.private? || ip.loopback?))
    end

    def is_trusted_ip?(env)
      return false if GlobalSetting.prometheus_trusted_ip_allowlist_regex.empty?
      begin
        trusted_ip_regex = Regexp.new GlobalSetting.prometheus_trusted_ip_allowlist_regex
        request = Rack::Request.new(env)
        ip = IPAddr.new(request.ip)
      rescue => e
        # failed to parse regex
        Discourse.warn_exception(
          e,
          message: "Error parsing prometheus trusted ip whitelist",
          env: env,
        )
      end
      !!(trusted_ip_regex && ip && ip.to_s =~ trusted_ip_regex)
    end

    def is_admin?(env)
      host = RailsMultisite::ConnectionManagement.host(env)
      result = false
      RailsMultisite::ConnectionManagement.with_hostname(host) do
        result = RailsMultisite::ConnectionManagement.current_db == "default"
        result &&= !!CurrentUser.lookup_from_env(env)&.admin
      end
      result
    end

    def intercept?(env)
      if env["PATH_INFO"] == "/metrics"
        return is_private_ip?(env) || is_trusted_ip?(env) || is_admin?(env)
      end
      false
    end

    def metrics(env)
      data =
        Net::HTTP.get(URI("http://localhost:#{GlobalSetting.prometheus_collector_port}/metrics"))
      [
        200,
        { "Content-Type" => "text/plain; charset=utf-8", "Content-Length" => data.bytesize.to_s },
        [data],
      ]
    end
  end
end
