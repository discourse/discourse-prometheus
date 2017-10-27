# frozen_string_literal: true

# This helper stores messages in memory till limit is reached
# once reached it pops out oldest messages
#
# Thread safe
class DiscoursePrometheus::BigPipe
  MAX_QUEUED = 10_000

  PROCESS_MESSAGE = SecureRandom.hex
  attr_reader :reader, :writer, :producer_reader, :producer_writer

  def initialize(max_messages, processor: nil, reporter: nil)
    @max_messages = max_messages

    @reader, @writer = IO.pipe
    @producer_reader, @producer_writer = IO.pipe

    @messages = []

    @lock = Mutex.new

    @processor = processor
    @reporter = reporter

    @consumer_thread = Thread.new do
      begin
        consumer_run_loop
      rescue => e
        Rails.logger.warn("Crashed in Prometheus message consumer #{e}")
      end
    end

    @producer_queue = Queue.new
    @producer_thread = nil
    @mutex = Mutex.new

  end

  def <<(msg)
    if @producer_queue.length > MAX_QUEUED
      STDERR.puts "Dropped metrics from #{Process.pid} cause producer queue is full"
    end

    ensure_producer_thread
    @producer_queue << msg
  end

  def ensure_producer_thread
    return if @producer_thread && @producer_thread.alive?

    @mutex.synchronize do
      return if @producer_thread && @producer_thread.alive?
      @producer_thread = Thread.new do
        begin
          producer_run_loop
        rescue => e
          Rails.logger.warn("Crashed in Prometheus message producer #{e}")
        end
      end
    end
  end

  def producer_run_loop
    while true
      Marshal.dump(@producer_queue.pop, @writer)
    end
  end

  def flush
    while @producer_queue.length > 0
      sleep 0
    end
  end

  def process
    return enum_for(:process) unless block_given?

    Marshal.dump(PROCESS_MESSAGE, @writer)

    count = @producer_reader.gets.to_i

    while count > 0
      yield Marshal.load(@producer_reader)
      count -= 1
    end
  end

  def destroy!
    @reader.close
    @writer.close
    @producer_reader.close
    @producer_writer.close
    @consumer_thread.kill
    @producer_thread.kill
  end

  private

  def consumer_run_loop
    while true
      message = Marshal.load(@reader)

      if message == PROCESS_MESSAGE
        messages = nil
        @lock.synchronize do
          messages = @messages
          @messages = [] unless @messages.length == 0
        end

        if @reporter
          begin
            messages = @reporter.report(messages)
          rescue => e
            Rails.logger.warn("Error reporting on messages #{e}")
            messages = []
          end
        end

        @producer_writer.puts messages.length
        messages.each do |m|
          Marshal.dump(m, @producer_writer)
        end
      else
        @lock.synchronize do
          if @processor
            message = @processor.process(message)
            if message
              @messages << message
            end
          else
            @messages << message
          end

          @messages.shift if @messages.length > @max_messages
        end
      end
    end
  end
end
