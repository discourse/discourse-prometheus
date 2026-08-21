# frozen_string_literal: true

module DiscoursePrometheus::Reporter
  class ImageProcessing
    def initialize(client)
      @client = client
    end

    def report(payload)
      metric = DiscoursePrometheus::InternalMetric::ImageProcessing.new
      DiscoursePrometheus::InternalMetric::ImageProcessing.attributes.each do |attribute|
        metric.public_send("#{attribute}=", payload.fetch(attribute))
      end
      @client.send_json(metric.to_h)
      nil
    end
  end
end
