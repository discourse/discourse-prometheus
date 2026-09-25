# frozen_string_literal: true

require "prometheus_exporter/server"
require_relative "../../lib/collector"

RSpec.describe DiscoursePrometheus do
  describe ":web_worker_timeout" do
    let(:port) { TCPServer.open("127.0.0.1", 0) { |socket| socket.addr[1] } }

    around do |example|
      original_client = $prometheus_client
      $prometheus_client = PrometheusExporter::Client.new(host: "127.0.0.1", port: port)
      example.run
    ensure
      $prometheus_client.stop
      $prometheus_client = original_client
    end

    it "delivers timeout events before their reporting processes exit" do
      collector = DiscoursePrometheus::Collector.new
      server =
        PrometheusExporter::Server::WebServer.new(
          port: port,
          bind: "127.0.0.1",
          collector: collector,
        )
      runner = server.start

      2.times do
        pid =
          fork do
            DiscourseEvent.trigger(:web_worker_timeout)
            Process.exit!(0)
          end
        _, status = Process.wait2(pid)
        expect(status).to be_success
      end

      wait_for(timeout: 5) do
        collector.prometheus_metrics_text.include?("pitchfork_worker_timeouts_total 2")
      end
      expect(collector.prometheus_metrics_text).to include(
        "pitchfork_worker_timeouts_total counter",
        "pitchfork_worker_timeouts_total 2",
      )
    ensure
      server&.stop
      runner&.join
    end

    it "returns when the collector is unavailable" do
      expect { DiscourseEvent.trigger(:web_worker_timeout) }.not_to raise_error
    end

    it "bounds reporting when the collector connection stalls" do
      allow(TCPSocket).to receive(:new) { sleep 30 }
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      DiscourseEvent.trigger(:web_worker_timeout)

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).to be < 3
    end
  end
end
