# frozen_string_literal: true

module DiscoursePrometheus::InternalMetric
  class Email < Base
    attribute :email_type, :db, :bounce
  end
end
