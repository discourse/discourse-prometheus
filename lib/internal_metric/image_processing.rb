# frozen_string_literal: true

module DiscoursePrometheus::InternalMetric
  class ImageProcessing < Base
    attribute(:operation, :result, :duration_seconds)
  end
end
