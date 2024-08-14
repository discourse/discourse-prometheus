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
