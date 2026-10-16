# frozen_string_literal: true

require "socket"
require "tmpdir"

RSpec.describe DiscoursePrometheus::ListenerStats do
  before { skip "Linux socket diagnostics are required" if RUBY_PLATFORM.exclude?("linux") }

  describe ".tcp" do
    it "counts queued and accepted connections while excluding other ports" do
      sockets = []
      begin
        server = TCPServer.new("127.0.0.1", 0)
        other_server = TCPServer.new("127.0.0.1", 0)
        sockets.concat([server, other_server])
        port = server.addr[1]
        sockets << TCPSocket.new("127.0.0.1", port)
        sockets << TCPSocket.new("127.0.0.1", port)
        sockets << TCPSocket.new("127.0.0.1", other_server.addr[1])
        sockets << other_server.accept

        expect(described_class.tcp(port).to_h).to eq(active: 0, queued: 2)

        sockets << server.accept

        expect(described_class.tcp(port).to_h).to eq(active: 1, queued: 1)

        sockets << server.accept

        expect(described_class.tcp(port).to_h).to eq(active: 2, queued: 0)
      ensure
        sockets.reverse_each(&:close)
      end
    end

    it "returns zero for an empty listener and an absent listener" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]

      expect(described_class.tcp(port).to_h).to eq(active: 0, queued: 0)
      server.close
      expect(described_class.tcp(port).to_h).to eq(active: 0, queued: 0)
    ensure
      server&.close
    end

    it "combines multipart replies" do
      record = [Socket::AF_INET, 10, 0, 0, 3000, 0].pack("CCCCnn")
      record << ("\0" * 48) << [3, 0, 0, 1].pack("LLLL")
      datagrams = [netlink_message(type: 20, payload: record), netlink_message(type: 3)]
      socket = diagnostic_socket(datagrams)
      Socket.stubs(:open).yields(socket)

      expect(described_class.tcp(3000).to_h).to eq(active: 0, queued: 3)
    end

    it "raises the kernel error instead of returning incomplete counts" do
      socket =
        diagnostic_socket([netlink_message(type: 2, payload: [-Errno::EPERM::Errno].pack("l"))])
      Socket.stubs(:open).yields(socket)

      expect { described_class.tcp(3000) }.to raise_error(Errno::EPERM)
    end

    it "rejects an interrupted dump" do
      socket = diagnostic_socket([netlink_message(type: 3, flags: 0x10)])
      Socket.stubs(:open).yields(socket)

      expect { described_class.tcp(3000) }.to raise_error(IOError, /Interrupted/)
    end

    it "rejects truncated datagrams" do
      socket = diagnostic_socket([netlink_message(type: 3)], flags: Socket::MSG_TRUNC)
      Socket.stubs(:open).yields(socket)

      expect { described_class.tcp(3000) }.to raise_error(IOError, /Truncated/)
    end

    it "rejects incomplete records" do
      socket = diagnostic_socket([netlink_message(type: 20, payload: "\0")])
      Socket.stubs(:open).yields(socket)

      expect { described_class.tcp(3000) }.to raise_error(IOError, /Incomplete/)
    end

    it "times out when diagnostics do not respond" do
      socket = diagnostic_socket([])
      socket.stubs(:wait_readable).returns(nil)
      Socket.stubs(:open).yields(socket)

      expect { described_class.tcp(3000) }.to raise_error(Timeout::Error)
    end
  end

  describe ".unix" do
    it "counts queued and accepted connections for the configured socket" do
      Dir.mktmpdir do |directory|
        sockets = []
        begin
          path = File.join(directory, "app socket")
          server = UNIXServer.new(path)
          other_server = UNIXServer.new(File.join(directory, "other"))
          sockets.concat([server, other_server])
          sockets << UNIXSocket.new(path)
          sockets << UNIXSocket.new(path)
          sockets << UNIXSocket.new(other_server.path)
          sockets << other_server.accept

          expect(described_class.unix(path).to_h).to eq(active: 0, queued: 2)

          sockets << server.accept

          expect(described_class.unix(path).to_h).to eq(active: 1, queued: 1)

          sockets << server.accept

          expect(described_class.unix(path).to_h).to eq(active: 2, queued: 0)
        ensure
          sockets.reverse_each(&:close)
        end
      end
    end

    it "resolves a relative socket symlink" do
      Dir.mktmpdir do |directory|
        server = UNIXServer.new(File.join(directory, "app"))
        link = File.join(directory, "alias")
        File.symlink("app", link)
        client = UNIXSocket.new(link)

        expect(described_class.unix(link).to_h).to eq(active: 0, queued: 1)
      ensure
        client&.close
        server&.close
      end
    end

    it "returns zero for an empty listener and an absent path" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "app")
        server = UNIXServer.new(path)

        expect(described_class.unix(path).to_h).to eq(active: 0, queued: 0)
        server.close
        expect(described_class.unix(File.join(directory, "absent")).to_h).to eq(
          active: 0,
          queued: 0,
        )
      ensure
        server&.close
      end
    end
  end

  def netlink_message(type:, payload: "", flags: 0)
    [payload.bytesize + 16, type, flags, 1, 0].pack("LSSLL") + payload
  end

  def diagnostic_socket(datagrams, flags: 0)
    socket = mock("socket diagnostics")
    socket.stubs(:send)
    socket.stubs(:wait_readable).returns(socket)
    unless datagrams.empty?
      socket.stubs(:recvmsg).returns(*datagrams.map { |data| [data, nil, flags] })
    end
    socket
  end
end
