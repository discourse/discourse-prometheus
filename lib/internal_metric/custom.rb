module DiscoursePrometheus::InternalMetric
  class Custom < Base
    attribute :name , :labels, :description, :value, :type

    def self.create_gauge_hash(name, description, value)
      metric = DiscoursePrometheus::InternalMetric::Custom.new
      metric.type = "Gauge"
      metric.name = name
      metric.description = description
      metric.value = value
      metric.to_h
    end
  end
end
