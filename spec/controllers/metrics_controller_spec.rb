require "rails_helper"

describe ::DiscoursePrometheus::MetricsController do
  routes { ::DiscoursePrometheus::Engine.routes }

  it "generates a correct status" do
    get :index
    expect(response.status).to eq(200)
    expect(response.content_type).to eq('text/plain')
  end
end
