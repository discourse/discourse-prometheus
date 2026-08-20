# frozen_string_literal: true

module DiscoursePrometheus::InternalMetric
  class ImageProcessing < Base
    attribute(:operation, :duration_seconds, :success)
  end
end
