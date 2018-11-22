module DiscoursePrometheus::InternalMetric
  class Custom < Base
    attribute :name , :labels, :description, :value, :type
  end
end
