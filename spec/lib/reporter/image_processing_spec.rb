# frozen_string_literal: true

RSpec.describe DiscoursePrometheus::Reporter::ImageProcessing do
  describe "#report" do
    it "sends an image-processing metric to the collector" do
      client = mock
      reporter = described_class.new(client)
      payload = { operation: "optimized_image_resize", duration_seconds: 1.25, success: false }

      client.expects(:send_json).with(payload.merge(_type: "ImageProcessing"))

      expect(reporter.report(payload)).to be_nil
    end
  end

  describe ":image_processing_finished" do
    it "rejects incomplete events without reporting observations" do
      $prometheus_client.expects(:send_json).never
      payload = { operation: "optimized_image_resize", duration_seconds: 0.25, success: true }

      %i[operation duration_seconds success].each do |missing_attribute|
        expect {
          DiscourseEvent.trigger(:image_processing_finished, payload.except(missing_attribute))
        }.to raise_error(KeyError, /#{missing_attribute}/)
      end
    end
  end
end
