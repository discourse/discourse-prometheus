require 'rails_helper'
require 'socket'
require 'net/http'

module DiscoursePrometheus
  describe WebServer do

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
      Collector.new
    end

    let :server do
      WebServer.new port: available_port, collector: collector
    end

    after do
      server.stop
      collector.stop
    end

    it "generates a correct status" do

      WebMock.allow_net_connect!
      server.start

      metric = InternalMetric::Web.get(tracked: true, status_code: 200, db: "bobsie")
      collector << metric

      collector.flush

      body = Net::HTTP.get(URI("http://localhost:#{available_port}/metrics"))

      expect(body).to include('bobsie')
    end
  end
end
