# frozen_string_literal: true
#
require_dependency "demon/base"

class DiscoursePrometheus::GlobalReporterDemon < ::Demon::Base
  def self.prefix
    "prometheus-global-reporter"
  end

  def suppress_stdout
    false
  end

  def suppress_stderr
    false
  end

  # Under pitchfork, Discourse calls this in its service worker (an idle
  # Discourse process) instead of forking a separate process for the reporter.
  def self.start_in_service_worker
    return if @service_worker_thread&.alive?
    @service_worker_thread = DiscoursePrometheus::Reporter::Global.start($prometheus_client)
  end

  def after_fork
    @logger.info("Starting Prometheus global reporter pid: #{Process.pid}")
    t = DiscoursePrometheus::Reporter::Global.start($prometheus_client)

    trap("INT") { DiscoursePrometheus::Reporter::Global.stop }
    trap("TERM") { DiscoursePrometheus::Reporter::Global.stop }
    trap("QUIT") { DiscoursePrometheus::Reporter::Global.stop }

    t.join
    @logger.info("Stopping Prometheus global reporter pid: #{Process.pid}")
    exit 0
  end
end
