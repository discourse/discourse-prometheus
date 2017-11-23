# frozen_string_literal: true
#
require_dependency 'middleware/request_tracker'

class DiscoursePrometheus::WebReporter

  attr_reader :collector

  def self.start(collector)
    instance = self.new(collector)
    Middleware::RequestTracker.register_detailed_request_logger(lambda do |env, data|
      instance.report(env, data)
    end)
  end

  def initialize(collector)
    @collector = collector
  end

  def report(env, data)
    # CAREFUL, we don't want to hoist env into Scheduler::Defer
    # hence the extra method call
    host = RailsMultisite::ConnectionManagement.host(env)
    log_prom_later(DiscoursePrometheus::InternalMetric::Web.from_env_data(env, data, host))
  end

  def log_prom_later(message)
    Scheduler::Defer.later("Prom stats", _db = nil) do
      @collector << message
    end
  end
end
