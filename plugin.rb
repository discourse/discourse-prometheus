# name: discourse-prometheus
# about: prometheus data collector for discourse
# version: 0.1
# authors: Sam Saffron

module ::DiscoursePrometheus; end

require_relative("lib/big_pipe")
require_relative("lib/prometheus_metric")
require_relative("lib/counter")
require_relative("lib/gauge")
require_relative("lib/summary")
require_relative("lib/metric")
require_relative("lib/reporter")
require_relative("lib/processor")
require_relative("lib/metric_collector")
require_relative("lib/process_collector")
require_relative("lib/process_metric")
require_relative("lib/job_metric")
require_relative("lib/middleware/metrics")
require_relative("lib/server")

GlobalSetting.add_default :prometheus_collector_port, 9405

Rails.configuration.middleware.unshift DiscoursePrometheus::Middleware::Metrics

after_initialize do
  $prometheus_collector = DiscoursePrometheus::MetricCollector.new
  DiscoursePrometheus::PrometheusMetric.default_prefix = 'discourse_'
  DiscoursePrometheus::Reporter.start($prometheus_collector)

  if Discourse.running_in_rack?
    $prometheus_web_server = DiscoursePrometheus::Server.new(collector: $prometheus_collector)
    $prometheus_web_server.start
  end

  # in dev we use puma and it runs in a single process
  if Rails.env == "development" && defined?(::Puma)
    DiscoursePrometheus::ProcessCollector.start($prometheus_collector, :web)
  end

  DiscourseEvent.on(:sidekiq_fork_started) do
    DiscoursePrometheus::ProcessCollector.start($prometheus_collector, :sidekiq)
  end

  DiscourseEvent.on(:web_fork_started) do
    DiscoursePrometheus::ProcessCollector.start($prometheus_collector, :web)
  end

  DiscourseEvent.on(:scheduled_job_ran) do |stat|
    metric = DiscoursePrometheus::JobMetric.new
    metric.scheduled = true
    metric.job_name = stat.name
    metric.duration = stat.duration_ms * 0.001
    $prometheus_collector << metric
  end

  DiscourseEvent.on(:sidekiq_job_ran) do |worker, msg, queue, duration|
    metric = DiscoursePrometheus::JobMetric.new
    metric.scheduled = false
    metric.duration = duration
    metric.job_name = worker.class.to_s
    $prometheus_collector << metric
  end
end
