# frozen_string_literal: true

require "socket"
require "timeout"

module DiscoursePrometheus
  class ListenerStats
    Counts = Data.define(:active, :queued)
    NETLINK_SOCK_DIAG = 4
    SOCK_DIAG_BY_FAMILY = 20
    NLMSG_ERROR = 2
    NLMSG_DONE = 3
    NLM_F_DUMP_INTR = 0x10
    TCP_ESTABLISHED = 1
    TCP_LISTEN = 10
    private_constant :Counts,
                     :NETLINK_SOCK_DIAG,
                     :SOCK_DIAG_BY_FAMILY,
                     :NLMSG_ERROR,
                     :NLMSG_DONE,
                     :NLM_F_DUMP_INTR,
                     :TCP_ESTABLISHED,
                     :TCP_LISTEN

    def self.unix(path)
      path = File.expand_path(File.readlink(path), File.dirname(path)) if File.symlink?(path)
      active = queued = 0
      File.foreach("/proc/net/unix", encoding: Encoding::BINARY) do |line|
        fields = line.split(nil, 8)
        next if fields.length != 8 || fields[7].chomp != path
        next if fields[3] != "00000000"

        case fields[5]
        when "02"
          queued += 1
        when "03"
          active += 1
        end
      end
      Counts.new(active:, queued:)
    end

    def self.tcp(port)
      request = [
        Socket::AF_INET,
        Socket::IPPROTO_TCP,
        0,
        0,
        (1 << TCP_ESTABLISHED) | (1 << TCP_LISTEN),
      ].pack("CCCCL")
      request << [port, 0].pack("nn") << ("\0" * 44)
      request = [request.bytesize + 16, SOCK_DIAG_BY_FAMILY, 0x301, 1, 0].pack("LSSLL") + request
      active = queued = 0
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2

      Socket.open(Socket::AF_NETLINK, Socket::SOCK_RAW, NETLINK_SOCK_DIAG) do |socket|
        socket.send(request, 0, [Socket::AF_NETLINK, 0, 0, 0].pack("SSLL"))
        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if remaining <= 0 || !socket.wait_readable(remaining)
            raise Timeout::Error, "Socket diagnostics timed out"
          end

          data, _sender, flags = socket.recvmsg(65_536)
          raise IOError, "Truncated socket diagnostics" if flags & Socket::MSG_TRUNC != 0

          offset = 0
          while offset < data.bytesize
            raise IOError, "Incomplete socket diagnostics header" if data.bytesize - offset < 16

            length, type, message_flags, sequence = data.unpack("LSSL", offset:)
            if length < 16 || offset + length > data.bytesize
              raise IOError, "Invalid socket diagnostics length"
            end
            raise IOError, "Unexpected socket diagnostics sequence" if sequence != 1
            if message_flags & NLM_F_DUMP_INTR != 0
              raise IOError, "Interrupted socket diagnostics dump"
            end

            if type == NLMSG_ERROR || type == NLMSG_DONE
              if length >= 20
                error = data.unpack1("l", offset: offset + 16)
                raise SystemCallError.new("Socket diagnostics", -error) if error != 0
              elsif type == NLMSG_ERROR
                raise IOError, "Incomplete socket diagnostics error"
              end
              return Counts.new(active:, queued:) if type == NLMSG_DONE
            elsif type == SOCK_DIAG_BY_FAMILY
              raise IOError, "Incomplete socket diagnostics record" if length < 88

              record = offset + 16
              if data.getbyte(record) == Socket::AF_INET &&
                   data.unpack1("n", offset: record + 4) == port &&
                   data.unpack1("L", offset: record + 68) != 0
                case data.getbyte(record + 1)
                when TCP_ESTABLISHED
                  active += 1
                when TCP_LISTEN
                  queued += data.unpack1("L", offset: record + 56)
                end
              end
            end
            offset += (length + 3) & ~3
          end
        end
      end
    end
  end
end
