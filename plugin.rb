# name: discourse-prometheus
# about: prometheus data collector for discourse
# version: 0.1
# authors: Sam Saffron

module ::DiscoursePrometheus; end

after_initialize do

  require_relative("lib/metric")
  require_relative("lib/reporter")
  require_relative("lib/collector")

  prom_reader, prom_writer = IO.pipe

  DiscoursePrometheus::Reporter.start(prom_writer)

  module ::DiscoursePrometheus
    class Engine < ::Rails::Engine
      engine_name 'discourse_prometheus'
      isolate_namespace ::DiscoursePrometheus
    end
  end

  load File.expand_path("../app/controllers/metrics_controller.rb", __FILE__)

  ::DiscoursePrometheus::Engine.routes.draw do
    get "/" => "metrics#index"
  end

  Discourse::Application.routes.append do
    mount ::DiscoursePrometheus::Engine, at: '/metrics'
  end

  require_dependency 'demon/sidekiq'
  class ::Demon::Sidekiq

    module Tracker

      def after_fork
        ::DiscoursePrometheus::Collector.start(prom_reader, *IO.pipe)
        super
      end
    end

    prepend Tracker
  end
end
