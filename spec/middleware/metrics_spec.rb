# frozen_string_literal: true

require "rails_helper"

describe ::DiscoursePrometheus::Middleware::Metrics do

  let :middleware do
    app = lambda { |env| [404, {}, ["not found"]] }
    ::DiscoursePrometheus::Middleware::Metrics.new(app)
  end

  it "will allow for trusted IP with prometheus_trusted_ip_whitelist_regex" do
    GlobalSetting.prometheus_trusted_ip_whitelist_regex = '^(200\.1)'
    status, = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '200.0.1.1', "rack.input" => StringIO.new)
    expect(status).to eq(200)
  end

  it "will 404 for unauthed if prometheus_trusted_ip_whitelist_regex is nil" do
    status, = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '200.0.1.1', "rack.input" => StringIO.new)
    expect(status).to eq(404)
  end

  it "will 404 for unauthed" do
    status, = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '200.0.1.1', "rack.input" => StringIO.new)
    expect(status).to eq(404)
  end

  it "will 404 for unauthed and invalid regex" do
    GlobalSetting.stubs(:prometheus_trusted_ip_whitelist_regex).returns("unbalanced bracket[")
    status, = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '200.0.1.1', "rack.input" => StringIO.new)
    expect(status).to eq(404)
  end

  it "will 404 for unauthed empty regex" do
    status, = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '200.0.1.1', "rack.input" => StringIO.new)
    expect(status).to eq(404)
  end

  it "can proxy the dedicated port" do
    stub_request(:get, "http://localhost:#{GlobalSetting.prometheus_collector_port}/metrics").
      to_return(status: 200, body: "hello world", headers: {})

    status, headers, body = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '192.168.1.1')
    body = body.join

    expect(status).to eq(200)
    expect(headers["Content-Type"]).to eq('text/plain; charset=utf-8')
    expect(body).to include('hello world')
  end

  it "can proxy the dedicated port with invalid regex" do
    GlobalSetting.stubs(:prometheus_trusted_ip_whitelist_regex).returns("unbalanced bracket[")
    stub_request(:get, "http://localhost:#{GlobalSetting.prometheus_collector_port}/metrics").
      to_return(status: 200, body: "hello world", headers: {})

    status, headers, body = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '192.168.1.1')
    body = body.join

    expect(status).to eq(200)
    expect(headers["Content-Type"]).to eq('text/plain; charset=utf-8')
    expect(body).to include('hello world')
  end

  it "can proxy the dedicated port on trusted IP" do
    GlobalSetting.stubs(:prometheus_trusted_ip_whitelist_regex).returns("(200\.0)")
    stub_request(:get, "http://localhost:#{GlobalSetting.prometheus_collector_port}/metrics").
      to_return(status: 200, body: "hello world", headers: {})

    status, headers, body = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '200.0.0.1')
    body = body.join

    expect(status).to eq(200)
    expect(headers["Content-Type"]).to eq('text/plain; charset=utf-8')
    expect(body).to include('hello world')
  end
end
