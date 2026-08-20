# frozen_string_literal: true

RSpec.describe DiscoursePrometheus::Reporter::ImageProcessing do
  describe "#report" do
    it "sends an image-processing metric to the collector" do
      client = mock
      reporter = described_class.new(client)
      payload = {
        operation: "optimized_image_resize",
        success: false,
        error_reason: "nonzero_exit",
        duration_seconds: 1.25,
        cpu_seconds: 0.75,
        max_rss_bytes: 64.megabytes,
      }

      client.expects(:send_json).with(payload.merge(_type: "ImageProcessing"))

      expect(reporter.report(payload)).to be_nil
    end
  end

  describe ":image_processing_finished" do
    it "rejects incomplete events without reporting observations" do
      allow(Rails.env).to receive(:test?).and_return(false)
      $prometheus_client.expects(:send_json).never
      incomplete_payload = {
        operation: "optimized_image_resize",
        success: true,
        error_reason: "none",
        duration_seconds: 0.25,
        cpu_seconds: 0.1,
      }

      expect {
        DiscourseEvent.trigger(:image_processing_finished, incomplete_payload)
      }.to raise_error(KeyError, /max_rss_bytes/)
    end
  end
end
