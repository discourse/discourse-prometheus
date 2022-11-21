# frozen_string_literal: true

describe ::DiscoursePrometheus::JobMetricInitializer do
  it "can enumerate regular jobs" do
    metrics = []
    DiscoursePrometheus::JobMetricInitializer.each_regular_job_metric { |m| metrics << m }
    expect(metrics.all? { |m| m.count == 0 }).to eq(true)
    expect(metrics.all? { |m| m.duration == 0 }).to eq(true)
    expect(metrics.map(&:job_name)).to include("Jobs::RunHeartbeat")
    expect(metrics.map(&:job_name)).not_to include("Jobs::Heartbeat")
  end

  it "can enumerate scheduled jobs" do
    Jobs::Heartbeat # ensure class is loaded (in prod, classes are eager-loaded)

    metrics = []
    DiscoursePrometheus::JobMetricInitializer.each_scheduled_job_metric { |m| metrics << m }
    expect(metrics.all? { |m| m.count == 0 }).to eq(true)
    expect(metrics.all? { |m| m.duration == 0 }).to eq(true)
    expect(metrics.all? { |m| m.scheduled == true }).to eq(true)
    expect(metrics.map(&:job_name)).to include("Jobs::Heartbeat")
    expect(metrics.map(&:job_name)).not_to include("Jobs::RunHeartbeat")
  end
end
