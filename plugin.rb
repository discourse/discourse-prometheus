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
require_relative("lib/middleware/metrics")

Rails.configuration.middleware.unshift DiscoursePrometheus::Middleware::Metrics

after_initialize do
  $prometheus_collector = DiscoursePrometheus::MetricCollector.new
  DiscoursePrometheus::PrometheusMetric.default_prefix = 'discourse_'
  DiscoursePrometheus::Reporter.start($prometheus_collector)
end
