# frozen_string_literal: true

# name: discourse-prometheus
# about: Collects key metrics from Discourse for Prometheus data analytics.
# meta_topic_id: 72666
# version: 0.1
# authors: Sam Saffron
# url: https://github.com/discourse/discourse-prometheus

module ::DiscoursePrometheus
end

gem "prometheus_exporter", "2.2.0"

require "prometheus_exporter/client"

require_relative("lib/internal_metric/base")
require_relative("lib/internal_metric/global")
require_relative("lib/internal_metric/job")
require_relative("lib/internal_metric/process")
require_relative("lib/internal_metric/web")
require_relative("lib/internal_metric/custom")

require_relative("lib/reporter/process")
require_relative("lib/reporter/global")
require_relative("lib/reporter/web")

require_relative("lib/collector_demon")
require_relative("lib/global_reporter_demon")

require_relative("lib/middleware/metrics")

require_relative("lib/job_metric_initializer")

GlobalSetting.add_default :prometheus_collector_port, 9405
GlobalSetting.add_default :prometheus_webserver_bind, "localhost"
GlobalSetting.add_default :prometheus_trusted_ip_allowlist_regex, ""
DiscoursePluginRegistry.define_filtered_register :global_collectors

Rails.configuration.middleware.unshift DiscoursePrometheus::Middleware::Metrics

after_initialize do
  require_relative("app/jobs/scheduled/update_stats")

  $prometheus_client =
    PrometheusExporter::Client.new(host: "localhost", port: GlobalSetting.prometheus_collector_port)

  # creates no new threads, this simply adds the instruments
  DiscoursePrometheus::Reporter::Web.start($prometheus_client) unless Rails.env.test?

  register_demon_process(DiscoursePrometheus::CollectorDemon)
  register_demon_process(DiscoursePrometheus::GlobalReporterDemon)

  on(:sidekiq_fork_started) do
    DiscoursePrometheus::Reporter::Process.start($prometheus_client, :sidekiq)
    DiscoursePrometheus::JobMetricInitializer.initialize_regular_job_metrics
    DiscoursePrometheus::JobMetricInitializer.initialize_scheduled_job_metrics
  end

  on(:web_fork_started) { DiscoursePrometheus::Reporter::Process.start($prometheus_client, :web) }

  on(:scheduled_job_ran) do |stat|
    metric = DiscoursePrometheus::InternalMetric::Job.new
    metric.scheduled = true
    metric.job_name = stat.name
    metric.duration = stat.duration_ms * 0.001
    metric.count = 1
    metric.success = stats.success
    $prometheus_client.send_json metric.to_h unless Rails.env.test?
  end

  on(:sidekiq_job_ran) do |worker, _msg, _queue, duration|
    metric = DiscoursePrometheus::InternalMetric::Job.new
    metric.scheduled = false
    metric.duration = duration
    metric.count = 1
    metric.job_name = worker.class.to_s
    metric.success = true
    $prometheus_client.send_json metric.to_h unless Rails.env.test?
  end

  on(:sidekiq_job_error) do |worker, _msg, _queue, duration|
    metric = DiscoursePrometheus::InternalMetric::Job.new
    metric.scheduled = false
    metric.duration = duration
    metric.count = 1
    metric.job_name = worker.class.to_s
    metric.success = false
    $prometheus_client.send_json metric.to_h unless Rails.env.test?
  end
end
