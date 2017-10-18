# frozen_string_literal: true
#
require_dependency 'middleware/request_tracker'

class DiscoursePrometheus::Reporter

  def self.start(writer)
    instance = self.new(writer)
    Middleware::RequestTracker.register_detailed_request_logger(lambda do |env, data|
      instance.report(env, data)
    end)
  end

  def initialize(writer)
    @writer = writer
  end

  def report(env, data)
    ad_params = env['action_dispatch.request.parameters']
    controller, action = nil

    if ad_params
      controller = ad_params['controller']
      action = ad_params['action']
    end

    path = env["REQUEST_PATH"]
    log_prom_later(path, controller, action, data)
  end

  def log_prom_later(path, controller, action, data)
    Scheduler::Defer.later("Prom stats", _db = nil) do
      $writer.puts("#{path} #{controller} #{action} #{data}")
    end
  end
end
