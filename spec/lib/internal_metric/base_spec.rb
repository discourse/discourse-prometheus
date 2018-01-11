require 'rails_helper'

module DiscoursePrometheus::InternalMetric
  describe Base do
    it "allows to_h on internal metrics" do

      job = Job.new
      job.job_name = "bob"
      job.scheduled = true
      job.duration = 100.1

      expect(job.to_h).to eq(
        job_name: "bob",
        scheduled: true,
        duration: 100.1,
        _type: "Job"
      )
    end

    it "implements from_h on internal metrics" do

      obj = {
        job_name: "bill",
        _type: "Job"
      }

      job = Base.from_h(obj)
      expect(job.class).to eq(Job)
      expect(job.job_name).to eq("bill")
    end

    it "implements from_h with string keys" do

      obj = {
        "job_name" => "bill",
        "_type" => "Job"
      }

      job = Base.from_h(obj)
      expect(job.class).to eq(Job)
      expect(job.job_name).to eq("bill")
    end
  end
end
