# frozen_string_literal: true

class ::DiscoursePrometheus::JobMetricInitializer
  def self.initialize_scheduled_job_metrics
    each_scheduled_job_metric { |metric| $prometheus_client.send_json metric.to_h }
  end

  def self.initialize_regular_job_metrics
    each_regular_job_metric { |metric| $prometheus_client.send_json metric.to_h }
  end

  def self.each_regular_job_metric
    # Enumerate all regular jobs and send a count=0 metric to the collector. This is not perfect - technically
    # any class can be passed to Jobs.enqueue. Discourse tends to pass a string to `Jobs.enqueue`, which is then
    # looked up from Jobs.constants, so this should cover the vast majority of cases
    ::Jobs.constants.each do |const|
      job_klass = ::Jobs.const_get(const)
      next if job_klass.class != Class
      next if job_klass == ::Jobs::Base

      ancestors = job_klass.ancestors

      if ancestors.include?(::Jobs::Base) && !ancestors.include?(::Jobs::Scheduled) &&
           !ancestors.include?(::Jobs::Onceoff)
        metric = DiscoursePrometheus::InternalMetric::Job.new
        metric.scheduled = false
        metric.duration = 0
        metric.count = 0
        metric.job_name = job_klass.name
        yield metric
      end
    end
  end

  def self.each_scheduled_job_metric
    # Enumerate all scheduled jobs and send a count=0 metric to the collector
    # to initialize the metric
    ::MiniScheduler::Manager.discover_schedules.each do |job_klass|
      metric = DiscoursePrometheus::InternalMetric::Job.new
      metric.scheduled = true
      metric.duration = 0
      metric.count = 0
      metric.job_name = job_klass.name
      yield metric
    end
  end
end
