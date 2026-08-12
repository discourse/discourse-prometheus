# frozen_string_literal: true

require "open3"
require "prometheus_exporter/server"
require "timeout"
require_relative "../../lib/collector"

RSpec.describe DiscoursePrometheus::Collector do
  describe "bin/collector" do
    it "starts without the Discourse application load path" do
      collector_path = File.expand_path("../../bin/collector", __dir__)
      environment = { "PROMETHEUS_EXPORTER_VERSION" => PrometheusExporter::VERSION }

      Open3.popen3(
        environment,
        collector_path,
        "0",
        "127.0.0.1",
        "0",
        "",
      ) do |stdin, stdout, stderr, wait_thread|
        stdin.close
        stdout.close

        expect(Timeout.timeout(10) { stderr.gets }).to include("Starting Prometheus Collector")
      ensure
        Process.kill("TERM", wait_thread.pid) if wait_thread.alive?
      end
    end
  end
end
