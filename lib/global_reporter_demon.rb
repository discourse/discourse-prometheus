# frozen_string_literal: true
#
require_dependency 'demon/base'

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
    STDERR.puts "#{Time.now}: Starting Prometheus global reporter pid: #{Process.pid}"
    t = DiscoursePrometheus::Reporter::Global.start($prometheus_client)

    trap('INT')  { DiscoursePrometheus::Reporter::Global.stop }
    trap('TERM') { DiscoursePrometheus::Reporter::Global.stop }
    trap('QUIT') { DiscoursePrometheus::Reporter::Global.stop }

    t.join
    STDERR.puts "#{Time.now}: Stopping Prometheus global reporter pid: #{Process.pid}"
    exit 0
  end
end
