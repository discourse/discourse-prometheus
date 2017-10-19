# name: discourse-prometheus
# about: prometheus data collector for discourse
# version: 0.1
# authors: Sam Saffron

module ::DiscoursePrometheus; end

after_initialize do

  require_relative("lib/big_pipe")
  require_relative("lib/prometheus_metric")
  require_relative("lib/counter")
  require_relative("lib/gauge")
  require_relative("lib/metric")
  require_relative("lib/reporter")
  require_relative("lib/processor")
  require_relative("lib/metric_collector")

  # TODO we may want to shrink the max here
  $prometheus_collector = DiscoursePrometheus::MetricCollector.new

  # TODO we want this configurable (discourse_) may be a better prefix
  DiscoursePrometheus::PrometheusMetric.default_prefix = 'web_'

  module ::DiscoursePrometheus
    class Engine < ::Rails::Engine
      engine_name 'discourse_prometheus'
      isolate_namespace ::DiscoursePrometheus
    end
  end

  require_relative("app/controllers/metrics_controller")

  ::DiscoursePrometheus::Engine.routes.draw do
    get "/" => "metrics#index"
  end

  Discourse::Application.routes.append do
    mount ::DiscoursePrometheus::Engine, at: '/metrics'
  end

  DiscoursePrometheus::Reporter.start($prometheus_collector)

  # TODO decide if we want to host this in sidekiq and not unicorn master
  # require_dependency 'demon/sidekiq'
  # class ::Demon::Sidekiq
  #
  #   module Tracker
  #     def after_fork
  #       ::DiscoursePrometheus::Collector.start($prom_reader, *IO.pipe)
  #       super
  #     end
  #   end
  #
  #   prepend Tracker
  # end
end
