require "rails_helper"

describe ::DiscoursePrometheus::Middleware::Metrics do

  let :middleware do
    app = lambda { |env| [404, {}, ["not found"]] }
    ::DiscoursePrometheus::Middleware::Metrics.new(app)
  end

  it "will 404 for unauthed" do
    status, = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '200.0.1.1', "rack.input" => StringIO.new)
    expect(status).to eq(404)
  end

  it "generates a correct status" do

    metric = DiscoursePrometheus::Metric.get(tracked: true, status_code: 200, db: "bobsie")
    $prometheus_collector << metric

    status, headers, body = middleware.call("PATH_INFO" => '/metrics', "REMOTE_ADDR" => '192.168.1.1')
    body = body.join

    expect(status).to eq(200)
    expect(headers["Content-Type"]).to eq('text/plain; charset=utf-8')
    expect(body).to include('master Redis')
    expect(body).to include('bobsie')
  end
end
