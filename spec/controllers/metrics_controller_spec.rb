require "rails_helper"

describe ::DiscoursePrometheus::MetricsController do
  routes { ::DiscoursePrometheus::Engine.routes }

  it "generates a correct status" do

    metric = DiscoursePrometheus::Metric.get(tracked: true, status_code: 200, host: "bobsie")
    $prometheus_collector << metric

    get :index
    expect(response.status).to eq(200)
    expect(response.content_type).to eq('text/plain')
    expect(response.body).to include('redis masters in a web')
    expect(response.body).to include('bobsie')
  end
end
