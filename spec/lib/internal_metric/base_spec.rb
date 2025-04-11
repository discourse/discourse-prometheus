# frozen_string_literal: true

RSpec.describe DiscoursePrometheus::InternalMetric::Base do
  it "allows #to_h on internal metrics" do
    job = DiscoursePrometheus::InternalMetric::Job.new
    job.job_name = "bob"
    job.scheduled = true
    job.duration = 100.1
    job.count = 1
    job.success = false

    expect(job.to_h).to eq(
      job_name: "bob",
      scheduled: true,
      duration: 100.1,
      count: 1,
      _type: "Job",
      success: false,
    )
  end

  it "implements #from_h on internal metrics" do
    obj = { job_name: "bill", _type: "Job" }

    job = described_class.from_h(obj)
    expect(job.class).to eq(DiscoursePrometheus::InternalMetric::Job)
    expect(job.job_name).to eq("bill")
  end

  it "implements #from_h with string keys" do
    obj = { "job_name" => "bill", "_type" => "Job" }

    job = described_class.from_h(obj)
    expect(job.class).to eq(DiscoursePrometheus::InternalMetric::Job)
    expect(job.job_name).to eq("bill")
  end
end
