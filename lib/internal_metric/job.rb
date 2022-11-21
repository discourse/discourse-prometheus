# frozen_string_literal: true

module DiscoursePrometheus::InternalMetric
  class Job < Base
    attribute :job_name, :scheduled, :duration, :count
  end
end
