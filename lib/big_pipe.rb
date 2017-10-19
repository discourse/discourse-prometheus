# frozen_string_literal: true

# This helper stores messages in memory till limit is reached
# once reached it pops out oldest messages
#
# Thread safe
class DiscoursePrometheus::BigPipe
  PROCESS_MESSAGE = SecureRandom.hex

  def initialize(max_messages)
    @max_messages = max_messages

    @reader, @writer = IO.pipe
    @producer_reader, @producer_writer = IO.pipe

    @messages = []

    @lock = Mutex.new

    @consumer_thread = Thread.new do
      begin
        consumer_run_loop
      rescue => e
        Rails.logger.warn("Crashed in Prometheus message consumer #{e}")
        STDERR.puts "#{e}"
      end
    end
  end

  def <<(msg)
    @writer.puts msg.to_s
  end

  def process
    return enum_for(:process) unless block_given?

    @writer.puts(PROCESS_MESSAGE)

    count = @producer_reader.gets.to_i
    while count > 0
      yield @producer_reader.gets.strip!
      count -= 1
    end
  end

  def destroy!
    @reader.close
    @writer.close
    @producer_reader.close
    @producer_writer.close
    @consumer_thread.kill
  end

  private

  def consumer_run_loop
    STDERR.puts "RUN LOOP STARTED #{Process.pid}"
    while true
      message = @reader.gets
      STDERR.puts "GOT MESSAGE #{object_id}"
      message.strip!

      if message == PROCESS_MESSAGE
        messages = nil
        @lock.synchronize do
          messages = @messages
          @messages = []
        end

        @producer_writer.puts messages.length
        messages.each do |m|
          @producer_writer.puts m
        end
      else
        @lock.synchronize do
          @messages << message
          @messages.shift if @messages.length > @max_messages
        end
      end
    end
  end
end
