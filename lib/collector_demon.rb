# frozen_string_literal: true
#
require_dependency "demon/base"

class DiscoursePrometheus::CollectorDemon < ::Demon::Base
  def self.prefix
    "prometheus-collector"
  end

  def run
    if @pid = fork
      write_pid_file
      return
    end

    collector = File.expand_path("../../bin/collector", __FILE__)

    exec collector,
         GlobalSetting.prometheus_collector_port.to_s,
         GlobalSetting.prometheus_webserver_bind,
         parent_pid.to_s,
         pid_file
  end
end
