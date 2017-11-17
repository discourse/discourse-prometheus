require 'rails_helper'
require 'socket'
require 'net/http'

module DiscoursePrometheus
  describe Server do

    let :available_port do
      port = 8080
      while port < 10_000
        begin
          TCPSocket.new("localhost", port).close
          port += 1
        rescue Errno::ECONNREFUSED
          break
        end
      end
      port
    end

    let :collector do
      MetricCollector.new
    end

    let :server do
      Server.new port: available_port, collector: collector
    end

    after do
      server.stop
      collector.stop
    end

    it "generates a correct status" do

      WebMock.allow_net_connect!
      server.start

      metric = DiscoursePrometheus::Metric.get(tracked: true, status_code: 200, db: "bobsie")
      collector << metric

      wait_for do
        server.global_metrics_collected
      end

      collector.flush

      body = Net::HTTP.get(URI("http://localhost:#{available_port}/metrics"))

      expect(body).to include('bobsie')
      expect(body).to include('master Redis')
    end
  end
end
