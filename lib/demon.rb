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

    env = "RUBY_GLOBAL_METHOD_CACHE_SIZE=2048 " \
      "RUBY_GC_HEAP_INIT_SLOTS=10000 "

    exec "#{env} #{collector} #{GlobalSetting.prometheus_collector_port} #{parent_pid}"
  end
end
