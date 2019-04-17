# name: discourse-prometheus
# about: prometheus data collector for discourse
# version: 0.1
# authors: Sam Saffron
# url: https://github.com/discourse/discourse-prometheus

module ::DiscoursePrometheus; end

# a bit odd but we need to read this from a version file
# cause this is loaded from the collector bin
gem 'prometheus_exporter', File.read(File.expand_path("../prometheus_exporter_version", __FILE__)).strip
require 'prometheus_exporter/client'

require_relative("lib/internal_metric/base")
require_relative("lib/internal_metric/global")
require_relative("lib/internal_metric/job")
require_relative("lib/internal_metric/process")
require_relative("lib/internal_metric/web")
require_relative("lib/internal_metric/custom")

require_relative("lib/reporter/process")
require_relative("lib/reporter/global")
require_relative("lib/reporter/web")

require_relative("lib/demon")

require_relative("lib/middleware/metrics")

GlobalSetting.add_default :prometheus_collector_port, 9405

Rails.configuration.middleware.unshift DiscoursePrometheus::Middleware::Metrics

after_initialize do
  $prometheus_client = PrometheusExporter::Client.new(
    host: 'localhost',
    port: GlobalSetting.prometheus_collector_port
  )

  # creates no new threads, this simply adds the instruments
  DiscoursePrometheus::Reporter::Web.start($prometheus_client)

  # happens once per rack application
  if Discourse.running_in_rack?
    Thread.new do
      begin
        DiscoursePrometheus::Demon.start
        while true
          DiscoursePrometheus::Demon.ensure_running
          sleep 1
        end
      rescue => e
        STDERR.puts "Failed to initialize prometheus web server from pid: #{Process.pid} #{e}"
      end
    end

    DiscoursePrometheus::Reporter::Global.start($prometheus_client)

    # in dev we may use puma and it runs in a single process
    if Rails.env == "development"
      DiscoursePrometheus::Reporter::Process.start($prometheus_client, :web)
    end
  end

  DiscourseEvent.on(:sidekiq_fork_started) do
    DiscoursePrometheus::Reporter::Process.start($prometheus_client, :sidekiq)
  end

  DiscourseEvent.on(:web_fork_started) do
    DiscoursePrometheus::Reporter::Process.start($prometheus_client, :web)
  end

  DiscourseEvent.on(:scheduled_job_ran) do |stat|
    metric = DiscoursePrometheus::InternalMetric::Job.new
    metric.scheduled = true
    metric.job_name = stat.name
    metric.duration = stat.duration_ms * 0.001
    $prometheus_client.send_json metric.to_h

    case stat.name
    when "Jobs::EnsurePostUploadsExistence"
      count = PostCustomField.where(name: Jobs::EnsurePostUploadsExistence::MISSING_UPLOADS).where.not(value: nil).count
      $prometheus_client.send_json DiscoursePrometheus::InternalMetric::Custom.create_gauge_hash(
        "missing_post_uploads",
        "Number of missing uploads in all posts",
        count
      )
    when "Jobs::EnsureS3UploadsExistence"
      count = Discourse.stats.get("missing_s3_uploads") || -1
      $prometheus_client.send_json DiscoursePrometheus::InternalMetric::Custom.create_gauge_hash(
        "missing_s3_uploads",
        "Number of missing uploads in S3",
        count
      )
    end
  end

  DiscourseEvent.on(:sidekiq_job_ran) do |worker, msg, queue, duration|
    metric = DiscoursePrometheus::InternalMetric::Job.new
    metric.scheduled = false
    metric.duration = duration
    metric.job_name = worker.class.to_s
    $prometheus_client.send_json metric.to_h
  end
end
