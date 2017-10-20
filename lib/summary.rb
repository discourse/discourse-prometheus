# frozen_string_literal: true

module DiscoursePrometheus
  class Summary < PrometheusMetric

    QUANTILES = [0.99, 0.9, 0.5, 0.1, 0.01]

    attr_reader :estimators, :count, :total

    def initialize(name, help)
      super
      @estimators = {}
    end

    def type
      "summary"
    end

    def metric_text
      text = String.new
      first = true
      @estimators.each do |labels, estimator|
        text << "\n" unless first
        first = false
        QUANTILES.each do |quantile|
          with_quantile = labels.merge(quantile: quantile)
          text << "#{prefix(@name)}#{labels_text(with_quantile)} #{estimator.query(quantile).to_f}\n"
        end
        text << "#{prefix(@name)}_sum#{labels_text(labels)} #{estimator.sum}\n"
        text << "#{prefix(@name)}_count#{labels_text(labels)} #{estimator.observations}"
      end
      text
    end

    def observe(value, labels = {})
      estimator = @estimators[labels] ||= Estimator.new
      estimator.observe(value.to_f)
    end

  end
end
