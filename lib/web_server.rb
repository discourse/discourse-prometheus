# frozen_string_literal: true

require 'webrick'
require 'timeout'

module DiscoursePrometheus
  class WebServer
    attr_reader :global_metrics_collected

    def initialize(port: GlobalSetting.prometheus_collector_port, collector:)

      @server = WEBrick::HTTPServer.new(
        Port: port,
        AccessLog: []
      )

      @collector = collector
      @port = port

      @server.mount_proc '/' do |req, res|
        res['ContentType'] = 'text/plain; charset=utf-8'
        if req.path == '/metrics'
          res.status = 200
          res.body = metrics
        else
          res.status = 404
          res.body = "Not Found! The Prometheus Discourse plugin only listens on /metrics"
        end
      end
    end

    def start
      @runner ||= Thread.start do
        begin
          @server.start
        rescue => e
          STDERR.puts "Failed to start prometheus collector web on port #{@port}: #{e}"
        end
      end
    end

    def stop
      @server.shutdown
    end

    def metrics
      metric_text = nil
      begin
        Timeout::timeout(2) do
          metric_text = @collector.prometheus_metrics_text
        end
      rescue Timeout::Error
        # we timed out ... bummer
        STDERR.puts "Generating Prometheus metrics text timed out"
      end

      @metrics = []

      add_gauge(
        "collector_working",
        "Is the master process collector able to collect metrics",
        metric_text.present? ? 1 : 0
      )

      <<~TEXT
      #{@metrics.map(&:to_prometheus_text).join("\n\n")}
      #{metric_text}
      TEXT
    end

    def add_gauge(name, help, value)
      gauge = ExternalMetric::Gauge.new(name, help)
      gauge.observe(value)
      @metrics << gauge
    end

  end
end
