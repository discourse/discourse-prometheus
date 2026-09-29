# frozen_string_literal: true
#
require_dependency "demon/base"

class DiscoursePrometheus::CollectorDemon < ::Demon::Base
  def self.prefix
    "prometheus-collector"
  end

  # With pitchfork reforking, Discourse runs this under its service keeper so
  # the collector (and the metrics it holds in memory) survives service worker
  # rotation; it then watches the server's supervisor instead of its parent.
  def server_lifetime_spec
    { "argv" => collector_argv(::Demon::Base.handoff_supervisor_pid), "env" => collector_env }
  end

  def run
    return super if respond_to?(:keeper_managed?) && keeper_managed?

    @pid =
      fork do
        ENV.update(collector_env)
        exec(*collector_argv(parent_pid))
      end

    Process.detach(@pid)

    write_pid_file
  end

  private

  def collector_argv(watched_pid)
    [
      File.expand_path("../../bin/collector", __FILE__),
      GlobalSetting.prometheus_collector_port.to_s,
      GlobalSetting.prometheus_webserver_bind,
      watched_pid.to_s,
      pid_file,
    ]
  end

  def collector_env
    {
      "RUBY_GLOBAL_METHOD_CACHE_SIZE" => "2048",
      "RUBY_GC_HEAP_INIT_SLOTS" => "10000",
      "PROMETHEUS_EXPORTER_VERSION" => PrometheusExporter::VERSION,
    }
  end
end
