# frozen_string_literal: true

require 'ipaddr'

module DiscoursePrometheus
  module Middleware; end
  class Middleware::Metrics

    def initialize(app, settings = {})
      @app = app
    end

    def call(env)
      if intercept?(env)
        metrics(env)
      else
        @app.call(env)
      end
    end

    private

    PRIVATE_IP = /^(127\.)|(192\.168\.)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(::1$)|([fF][cCdD])/

    def is_private_ip?(env)
      request = Rack::Request.new(env)
      ip = IPAddr.new(request.ip) rescue nil
      !!(ip && ip.to_s =~ PRIVATE_IP)
    end

    def is_trusted_ip?(env)
      trusted_ip_regex = Regexp.new GlobalSetting.prometheus_trusted_ip_whitelist_regex rescue nil
      request = Rack::Request.new(env)
      ip = IPAddr.new(request.ip) rescue nil
      !!(trusted_ip_regex && ip && ip.to_s =~ trusted_ip_regex)
    end

    def is_admin?(env)
      host = RailsMultisite::ConnectionManagement.host(env)
      result = false
      RailsMultisite::ConnectionManagement.with_hostname(host) do
        result = !!CurrentUser.lookup_from_env(env)&.admin
      end
      result
    end

    def intercept?(env)
      if env["PATH_INFO"] == "/metrics"
        return is_private_ip?(env) || is_admin?(env) || is_trusted_ip?(env)
      end
      false
    end

    def metrics(env)
      data = Net::HTTP.get(URI("http://localhost:#{GlobalSetting.prometheus_collector_port}/metrics"))
      [200, {
        "Content-Type" => "text/plain; charset=utf-8",
        "Content-Length" => data.bytesize.to_s
      }, [data]]
    end

  end
end
