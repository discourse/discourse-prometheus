module DiscoursePrometheus::InternalMetric
  class Job < Base
    attribute :job_name, :scheduled, :duration
  end
end
