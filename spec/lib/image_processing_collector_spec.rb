# frozen_string_literal: true

require "prometheus_exporter/server"
require_relative "../../lib/collector"

RSpec.describe DiscoursePrometheus::Collector do
  subject(:collector) { described_class.new }

  describe "#process" do
    it "observes successful and failed image-processing results in all histograms" do
      successful_metric = DiscoursePrometheus::InternalMetric::ImageProcessing.new
      successful_metric.operation = "optimized_image_resize"
      successful_metric.success = true
      successful_metric.error_reason = "none"
      successful_metric.duration_seconds = 0.25
      successful_metric.cpu_seconds = 0.1
      successful_metric.max_rss_bytes = 16.megabytes

      failed_metric = DiscoursePrometheus::InternalMetric::ImageProcessing.new
      failed_metric.operation = "topic_og_render"
      failed_metric.success = false
      failed_metric.error_reason = "wall_timeout"
      failed_metric.duration_seconds = 20
      failed_metric.cpu_seconds = 10
      failed_metric.max_rss_bytes = 128.megabytes

      collector.process(successful_metric.to_json)
      collector.process(failed_metric.to_json)

      metrics = collector.prometheus_metrics.index_by(&:name)
      successful_labels = {
        "operation" => "optimized_image_resize",
        "success" => "true",
        "error_reason" => "none",
      }
      failed_labels = {
        "operation" => "topic_og_render",
        "success" => "false",
        "error_reason" => "wall_timeout",
      }

      expect(metrics.keys).to include(
        "image_processing_duration_seconds",
        "image_processing_cpu_seconds",
        "image_processing_max_rss_bytes",
      )
      expect(metrics["image_processing_duration_seconds"].buckets).to eq(
        [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 20, 30],
      )
      expect(metrics["image_processing_duration_seconds"].to_h).to eq(
        successful_labels => {
          "count" => 1,
          "sum" => 0.25,
        },
        failed_labels => {
          "count" => 1,
          "sum" => 20.0,
        },
      )
      expect(metrics["image_processing_cpu_seconds"].buckets).to eq(
        [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120, 300],
      )
      expect(metrics["image_processing_cpu_seconds"].to_h).to eq(
        successful_labels => {
          "count" => 1,
          "sum" => 0.1,
        },
        failed_labels => {
          "count" => 1,
          "sum" => 10.0,
        },
      )
      expect(metrics["image_processing_max_rss_bytes"].buckets).to eq(
        [1, 4, 16, 64, 128, 256, 512, 1024, 2048, 4096].map(&:megabytes),
      )
      expect(metrics["image_processing_max_rss_bytes"].to_h).to eq(
        successful_labels => {
          "count" => 1,
          "sum" => 16.megabytes.to_f,
        },
        failed_labels => {
          "count" => 1,
          "sum" => 128.megabytes.to_f,
        },
      )
    end
  end

  describe "#prometheus_metrics_text" do
    it "exports an image-processing event through the public Prometheus exposition" do
      original_prefix = PrometheusExporter::Metric::Base.default_prefix
      PrometheusExporter::Metric::Base.default_prefix = "discourse_"
      allow(Rails.env).to receive(:test?).and_return(false)
      allow($prometheus_client).to receive(:send_json) do |metric|
        collector.process(Oj.dump(metric, mode: :object))
      end

      expect(collector.prometheus_metrics_text).to be_empty

      DiscourseEvent.trigger(
        :image_processing_finished,
        {
          operation: "optimized_image_crop",
          success: false,
          error_reason: "nonzero_exit",
          duration_seconds: 0.25,
          cpu_seconds: 0.1,
          max_rss_bytes: 16.megabytes,
        },
      )

      metrics_text = collector.prometheus_metrics_text

      expect(metrics_text).to include(
        "# TYPE discourse_image_processing_duration_seconds histogram",
        "# TYPE discourse_image_processing_cpu_seconds histogram",
        "# TYPE discourse_image_processing_max_rss_bytes histogram",
        'discourse_image_processing_duration_seconds_bucket{operation="optimized_image_crop",success="false",error_reason="nonzero_exit",le="0.25"} 1',
        'discourse_image_processing_duration_seconds_count{operation="optimized_image_crop",success="false",error_reason="nonzero_exit"} 1',
        'discourse_image_processing_duration_seconds_sum{operation="optimized_image_crop",success="false",error_reason="nonzero_exit"} 0.25',
      )
    ensure
      PrometheusExporter::Metric::Base.default_prefix = original_prefix
    end
  end
end
