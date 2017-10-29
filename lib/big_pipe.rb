# frozen_string_literal: true

# This helper stores messages in memory till limit is reached
# once reached it pops out oldest messages
#
# Thread safe
class DiscoursePrometheus::BigPipe

  class RobustPipe
    SEP = "\x00\x01\x02"
    REPLACE_SEP = SecureRandom.bytes(16)

    def initialize
      @reader, @writer = IO.pipe
      @reader.binmode
      @writer.binmode

      @buffer = String.new
    end

    def <<(data)
      encoded = encode(Marshal.dump(data))
      @writer.syswrite(encoded << SEP)
    end

    def read
      while !has_object?
        @buffer << @reader.sysread(10_000)
      end
      next_object
    end

    def close
      @writer.close
      @reader.close
    end

    private

    def has_object?
      @buffer.include? SEP
    end

    def next_object
      i = @buffer.index(SEP)
      encoded = @buffer[0..i]
      @buffer[0..i + SEP.length - 1] = ''
      decode(encoded)
    end

    def decode(data)
      data.gsub!(REPLACE_SEP, SEP)
      Marshal.load(data)
    end

    def encode(data)
      if data.include? SEP
        data.gsub(SEP, REPLACE_SEP)
      else
        data
      end
    end
  end

  MAX_QUEUED = 10_000

  PROCESS_MESSAGE = SecureRandom.hex
  attr_reader :consumer_pipe, :reporter_pipe

  def initialize(max_messages, processor: nil, reporter: nil)
    @max_messages = max_messages

    @consumer_pipe = RobustPipe.new
    @reporter_pipe = RobustPipe.new

    @messages = []

    @lock = Mutex.new

    @processor = processor
    @reporter = reporter

    @consumer_thread = Thread.new do
      while true
        begin
          consumer_run_loop
        rescue => e
          puts caller
          STDERR.puts "Crashed in Prometheus consumer #{e}, recovering"
          Rails.logger.warn("Crashed in Prometheus message consumer #{e}")
        end
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
          STDERR.puts("Crashed in Prometheus message producer #{e} will recover after next metric")
          Rails.logger.warn("Crashed in Prometheus message producer #{e} will recover afer next metric")
        end
      end
    end
  end

  def producer_run_loop
    while true
      @consumer_pipe << @producer_queue.pop
    end
  end

  def flush
    while @producer_queue.length > 0
      sleep 0
    end
  end

  def process
    return enum_for(:process) unless block_given?

    @consumer_pipe << PROCESS_MESSAGE

    count = @reporter_pipe.read

    while count > 0
      yield @reporter_pipe.read
      count -= 1
    end
  end

  def destroy!
    @consumer_thread.kill
    @producer_thread.kill
    @consumer_pipe.close
    @reporter_pipe.close
  end

  private

  def consumer_run_loop
    while true
      message = @consumer_pipe.read

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
            STDERR.puts("Error reporting on messages in prometheus Discourse #{e}")
            Rails.logger.warn("Error reporting on messages #{e}")
            messages = []
          end
        end

        @reporter_pipe << messages.length
        messages.each do |m|
          @reporter_pipe << m
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
