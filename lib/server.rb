# frozen_string_literal: true

require 'webrick'
require 'timeout'

module DiscoursePrometheus
  class Server
    attr_reader :global_metrics_collected

    def initialize(port: GlobalSetting.prometheus_collector_port, collector:)

      @server = WEBrick::HTTPServer.new(
        Port: port,
        AccessLog: []
      )

      @collector = collector
      @port = port
      @global_metrics_collected = false

      # collect globals every 5 seconds
      # recycle all stats every 30
      # this happens cause we do a max on queued and active reqs
      @collect_new_global_seconds = 30
      @collect_global_seconds = 5

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
      @global_collector ||= Thread.start do
        metrics = GlobalMetric.new
        i = 0

        while true
          begin
            # collect new stats every 30 seconds
            metrics = GlobalMetric.new if i % (@collect_new_global_seconds / @collect_global_seconds) == 0
            i += 1
            metrics.collect
            @collector << metrics
            @global_metrics_collected = true
          rescue => e
            STDERR.puts "Error collecting global metrics #{e}"
            Rails.logger.warn("Error collecting global metrics #{e}") rescue nil
          end
          sleep @collect_global_seconds
        end
      end
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
      @global_collector.kill if @global_collector && @global_collector.alive?
      @global_collector = nil
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
      gauge = Gauge.new(name, help)
      gauge.observe(value)
      @metrics << gauge
    end

  end
end
