# frozen_string_literal: true

module DiscoursePrometheus
  class NullMetric < ::DiscoursePrometheus::InternalMetric::Custom
    attribute :name, :labels, :description, :value, :type

    def initialize
      @name = "null_metric"
      @description = "Testing"
      @type = "Gauge"
    end

    def collect
      @value = 1
    end
  end
end
