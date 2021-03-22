# frozen_string_literal: true

require "rails_helper"

describe ::DiscoursePrometheus::Middleware::Metrics do

  let :middleware do
    app = lambda { |env| [404, {}, ["not found"]] }
    ::DiscoursePrometheus::Middleware::Metrics.new(app)
  end

  it "will 404 for unauthed if prometheus_trusted_ip_allowlist_regex is unset" do
    status, = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '200.0.1.1', "rack.input" => StringIO.new)
    expect(status).to eq(404)
  end

  it "will 404 for unauthed" do
    status, = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '200.0.1.1', "rack.input" => StringIO.new)
    expect(status).to eq(404)
  end

  it "will 404 for unauthed and invalid regex" do
    global_setting :prometheus_trusted_ip_allowlist_regex, "unbalanced bracket["
    status, = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '200.0.1.1', "rack.input" => StringIO.new)
    expect(status).to eq(404)
  end

  it "will 404 for unauthed empty regex" do
    status, = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '200.0.1.1', "rack.input" => StringIO.new)
    expect(status).to eq(404)
  end

  it "will 404 for public IP addresses" do
    addresses = %w[62.127.0.1 62.192.168.1 62.10.0.0 62.172.16.0 62.172.21.0 62.172.31.0 2001:fc00:ffff:ffff:ffff:ffff:ffff:ffff]
    addresses.each do |ip|
      status, = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => ip, "rack.input" => StringIO.new)
      expect(status).to eq(404)
    end
  end

  it "can proxy the dedicated port for private IP addresses" do
    stub_request(:get, "http://localhost:#{GlobalSetting.prometheus_collector_port}/metrics").
      to_return(status: 200, body: "hello world", headers: {})

    addresses = %w[127.1.2.3 192.168.1.2 10.0.1.2 172.16.9.8 172.19.1.2 172.20.9.8 172.29.1.2 172.30.9.8 172.31.1.2]
    addresses.each do |ip|
      status, headers, body = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => ip)
      body = body.join

      expect(status).to eq(200)
      expect(headers["Content-Type"]).to eq('text/plain; charset=utf-8')
      expect(body).to include('hello world')
    end
  end

  it "can proxy the dedicated port even with invalid regex" do
    global_setting :prometheus_trusted_ip_allowlist_regex, "unbalanced bracket["
    stub_request(:get, "http://localhost:#{GlobalSetting.prometheus_collector_port}/metrics").
      to_return(status: 200, body: "hello world", headers: {})

    status, headers, body = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '192.168.1.1')
    body = body.join

    expect(status).to eq(200)
    expect(headers["Content-Type"]).to eq('text/plain; charset=utf-8')
    expect(body).to include('hello world')
  end

  it "can proxy the dedicated port on trusted IP" do
    global_setting :prometheus_trusted_ip_allowlist_regex, "(200\.0)"
    stub_request(:get, "http://localhost:#{GlobalSetting.prometheus_collector_port}/metrics").
      to_return(status: 200, body: "hello world", headers: {})

    status, headers, body = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '200.0.0.1')
    body = body.join

    expect(status).to eq(200)
    expect(headers["Content-Type"]).to eq('text/plain; charset=utf-8')
    expect(body).to include('hello world')
  end
end
