# frozen_string_literal: true

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

require_relative("lib/collector_demon")
require_relative("lib/global_reporter_demon")

require_relative("lib/middleware/metrics")

GlobalSetting.add_default :prometheus_collector_port, 9405
GlobalSetting.add_default :prometheus_trusted_ip_allowlist_regex, ''

Rails.configuration.middleware.unshift DiscoursePrometheus::Middleware::Metrics

after_initialize do
  if GlobalSetting.respond_to?(:prometheus_trusted_ip_whitelist_regex) && GlobalSetting.prometheus_trusted_ip_allowlist_regex.blank?
    Discourse.deprecate("prometheus_trusted_ip_whitelist_regex is deprecated, use the prometheus_trusted_ip_allowlist_regex.", drop_from: "2.6")
    GlobalSetting.define_singleton_method("prometheus_trusted_ip_allowlist_regex") do
      GlobalSetting.prometheus_trusted_ip_whitelist_regex
    end
  end

  $prometheus_client = PrometheusExporter::Client.new(
    host: 'localhost',
    port: GlobalSetting.prometheus_collector_port
  )

  # creates no new threads, this simply adds the instruments
  DiscoursePrometheus::Reporter::Web.start($prometheus_client) unless Rails.env.test?

  if respond_to? :register_demon_process
    register_demon_process(DiscoursePrometheus::CollectorDemon)
    register_demon_process(DiscoursePrometheus::GlobalReporterDemon)
  elsif Discourse.running_in_rack?
    # TODO: Remove once Discourse 2.7 stable is released
    Thread.new do
      begin
        DiscoursePrometheus::CollectorDemon.start
        DiscoursePrometheus::GlobalReporterDemon.start
        while true
          DiscoursePrometheus::CollectorDemon.ensure_running
          DiscoursePrometheus::GlobalReporterDemon.ensure_running
          sleep 5
        end
      rescue => e
        STDERR.puts "Failed to initialize prometheus demons from pid: #{Process.pid} #{e}"
      end
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
    $prometheus_client.send_json metric.to_h unless Rails.env.test?
  end

  DiscourseEvent.on(:sidekiq_job_ran) do |worker, msg, queue, duration|
    metric = DiscoursePrometheus::InternalMetric::Job.new
    metric.scheduled = false
    metric.duration = duration
    metric.job_name = worker.class.to_s
    $prometheus_client.send_json metric.to_h unless Rails.env.test?
  end
end
