class DiscoursePrometheus::Gauge < DiscoursePrometheus::PrometheusMetric

  attr_reader :data

  def initialize(name, help)
    super
    @data = {}
  end

  def type
    "gauge"
  end

  def metric_text
    @data.map do |labels, value|
      "#{prefix(@name)}#{labels_text(labels)} #{value}"
    end.join("\n")
  end

  def observe(value, labels = {})
    @data[labels] = value
  end

end
