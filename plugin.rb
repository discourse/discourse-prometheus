# name: discourse-prometheus
# about: prometheus data collector for discourse
# version: 0.1
# authors: Sam Saffron

module ::DiscoursePrometheus; end

require_relative("lib/big_pipe")
require_relative("lib/external_metric/base")
require_relative("lib/external_metric/counter")
require_relative("lib/external_metric/gauge")
require_relative("lib/external_metric/summary")

require_relative("lib/internal_metric/global")
require_relative("lib/internal_metric/job")
require_relative("lib/internal_metric/process")
require_relative("lib/internal_metric/web")

require_relative("lib/web_reporter")
require_relative("lib/process_reporter")

require_relative("lib/processor")
require_relative("lib/collector")

require_relative("lib/middleware/metrics")
require_relative("lib/web_server")

GlobalSetting.add_default :prometheus_collector_port, 9405

Rails.configuration.middleware.unshift DiscoursePrometheus::Middleware::Metrics

after_initialize do
  $prometheus_collector = DiscoursePrometheus::Collector.new
  DiscoursePrometheus::ExternalMetric::Base.default_prefix = 'discourse_'
  DiscoursePrometheus::WebReporter.start($prometheus_collector)

  if Discourse.running_in_rack?
    Thread.new do
      begin
        $prometheus_web_server = DiscoursePrometheus::WebServer.new(collector: $prometheus_collector)
        $prometheus_web_server.start
      rescue Errno::EADDRINUSE
        STDERR.puts "Not initializing prometheus web server in pid: #{Process.pid}, port is in use will retry in 10 seconds!"
        sleep 10
        retry
      rescue => e
        STDERR.puts "Failed to initialize prometheus web server in pid: #{Process.pid} #{e}"
      end
    end
  end

  # in dev we use puma and it runs in a single process
  if Rails.env == "development" && defined?(::Puma)
    DiscoursePrometheus::ProcessReporter.start($prometheus_collector, :web)
  end

  DiscourseEvent.on(:sidekiq_fork_started) do
    DiscoursePrometheus::ProcessReporter.start($prometheus_collector, :sidekiq)
  end

  DiscourseEvent.on(:web_fork_started) do
    DiscoursePrometheus::ProcessReporter.start($prometheus_collector, :web)
  end

  DiscourseEvent.on(:scheduled_job_ran) do |stat|
    metric = DiscoursePrometheus::InternalMetric::Job.new
    metric.scheduled = true
    metric.job_name = stat.name
    metric.duration = stat.duration_ms * 0.001
    $prometheus_collector << metric
  end

  DiscourseEvent.on(:sidekiq_job_ran) do |worker, msg, queue, duration|
    metric = DiscoursePrometheus::InternalMetric::Job.new
    metric.scheduled = false
    metric.duration = duration
    metric.job_name = worker.class.to_s
    $prometheus_collector << metric
  end
end
