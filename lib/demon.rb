require_dependency 'demon/base'

class DiscoursePrometheus::Demon < Demon::Base
  def self.prefix
    "prometheus-demon"
  end

  def run
    if @pid = fork
      write_pid_file
      return
    end

    collector = File.expand_path("../../bin/collector", __FILE__)
    exec "#{collector} #{GlobalSetting.prometheus_collector_port} #{parent_pid}"
  end
end
