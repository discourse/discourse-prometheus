# frozen_string_literal: true

module DiscoursePrometheus::InternalMetric
  class ImageProcessing < Base
    attribute(:operation, :success, :error_reason, :duration_seconds, :cpu_seconds, :max_rss_bytes)
  end
end
