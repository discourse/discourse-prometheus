# frozen_string_literal: true

if Rails.autoloaders.main.class == Zeitwerk::Loader
  require_dependency 'demon/demon_base'
else
  require_dependency 'demon/base'
end

base_class = Rails.autoloaders.main.class == Zeitwerk::Loader ? Demon::DemonBase : Demon::Base

class DiscoursePrometheus::Demon < base_class
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
