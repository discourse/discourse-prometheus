# frozen_string_literal: true
#
require_dependency 'middleware/request_tracker'

class DiscoursePrometheus::Reporter

  attr_reader :pipe

  def self.start(pipe)
    instance = self.new(pipe)
    Middleware::RequestTracker.register_detailed_request_logger(lambda do |env, data|
      instance.report(env, data)
    end)
  end

  def initialize(pipe)
    @pipe = pipe
  end

  def report(env, data)
    # CAREFUL, we don't want to hoist env into Scheduler::Defer
    # hence the extra method call
    host = RailsMultisite::ConnectionManagement.host(env)
    log_prom_later(DiscoursePrometheus::Metric.from_env_data(env, data, host))
  end

  def log_prom_later(message)
    Scheduler::Defer.later("Prom stats", _db = nil) do
      STDERR.puts(message.to_s + " pipe #{@pipe.object_id}")
      @pipe << message.to_s
    end
  end
end
