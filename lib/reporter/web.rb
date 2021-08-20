# frozen_string_literal: true
#
require 'middleware/request_tracker'

class DiscoursePrometheus::Reporter::Web

  attr_reader :client

  def self.start(client)
    instance = self.new(client)
    Middleware::RequestTracker.register_detailed_request_logger(lambda do |env, data|
      instance.report(env, data)
    end)
  end

  def initialize(client)
    @client = client
  end

  def report(env, data)
    # CAREFUL, we don't want to hoist env into Scheduler::Defer
    # hence the extra method call
    host = RailsMultisite::ConnectionManagement.host(env)
    log_prom_later(::DiscoursePrometheus::InternalMetric::Web.from_env_data(env, data, host))
  end

  def log_prom_later(metric)
    Scheduler::Defer.later("Prom stats", _db = nil) do
      @client.send_json metric
    end
  end
end
