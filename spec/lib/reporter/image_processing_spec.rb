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
end
