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
    # CAREFUL, we don't want to hoist env into Scheduler::Defer
    # hence the extra method call
    log_prom_later(DiscoursePrometheus::Metric.from_env_data(env, data))
  end

  def log_prom_later(message)
    Scheduler::Defer.later("Prom stats", _db = nil) do
      @writer.puts(message.to_s)
    end
  end
end
