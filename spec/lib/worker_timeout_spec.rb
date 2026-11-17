# frozen_string_literal: true

require "prometheus_exporter/server"
require_relative "../../lib/collector"

RSpec.describe DiscoursePrometheus do
  describe ":web_worker_timeout" do
    it "increments the timeout counter through the shared client" do
      collector = DiscoursePrometheus::Collector.new
      allow($prometheus_client).to receive(:send_json) do |metric, sync:|
        expect(sync).to eq(true)
        collector.process(Oj.dump(metric, mode: :object))
      end

      2.times { DiscourseEvent.trigger(:web_worker_timeout) }

      expect(collector.prometheus_metrics_text).to include(
        "pitchfork_worker_timeouts_total counter",
        "pitchfork_worker_timeouts_total 2",
      )
    end
  end
end
