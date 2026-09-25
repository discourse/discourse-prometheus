# frozen_string_literal: true

require "timeout"

module DiscoursePrometheus::Reporter
  class WorkerTimeout
    def report
      metric = DiscoursePrometheus::InternalMetric::Custom.new
      metric.type = "Counter"
      metric.name = "pitchfork_worker_timeouts_total"
      metric.description = "Total number of Pitchfork soft worker timeouts"
      metric.value = 1

      client =
        PrometheusExporter::Client.new(
          host: "localhost",
          port: GlobalSetting.prometheus_collector_port,
          process_queue_once_and_stop: true,
        )

      Timeout.timeout(1) do
        begin
          client.send_json(metric.to_h)
        ensure
          client.stop
        end
      end
    rescue => error
      Rails.logger.warn("Failed to report worker timeout: #{error.message}")
    end
  end
end
