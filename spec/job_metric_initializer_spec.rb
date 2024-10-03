# frozen_string_literal: true

RSpec.describe DiscoursePrometheus::JobMetricInitializer do
  it "enumerates regular jobs" do
    metrics = []
    DiscoursePrometheus::JobMetricInitializer.each_regular_job_metric { |m| metrics << m }
    expect(metrics.all? { |m| m.count == 0 }).to eq(true)
    expect(metrics.all? { |m| m.duration == 0 }).to eq(true)
    expect(metrics.map(&:job_name)).to include("Jobs::RunHeartbeat")
    expect(metrics.map(&:job_name)).not_to include("Jobs::Heartbeat")
  end

  it "enumerates scheduled jobs" do
    # ensure class is loaded (in prod, classes are eager-loaded)
    expect(Jobs::Heartbeat).to be_present

    metrics = []
    DiscoursePrometheus::JobMetricInitializer.each_scheduled_job_metric { |m| metrics << m }
    expect(metrics.all? { |m| m.count == 0 }).to eq(true)
    expect(metrics.all? { |m| m.duration == 0 }).to eq(true)
    expect(metrics.all? { |m| m.scheduled == true }).to eq(true)
    expect(metrics.map(&:job_name)).to include("Jobs::Heartbeat")
    expect(metrics.map(&:job_name)).not_to include("Jobs::RunHeartbeat")
  end
end
