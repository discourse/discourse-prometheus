require 'rails_helper'

module DiscoursePrometheus
  describe BigPipe do
    after do
      @pipe.destroy! if @pipe
    end

    def new_pipe(size, processor: nil, reporter: nil)
      @pipe.destroy! if @pipe
      @pipe = BigPipe.new(size, processor: processor, reporter: reporter)
    end

    class DropSeconds
      def initialize
        @i = 0
      end

      def process(message)
        @i += 1
        if @i % 2 == 0
          nil
        else
          message
        end
      end
    end

    class Doubler
      def report(messages)
        messages + messages
      end
    end

    it "can process no messages" do
      pipe = new_pipe(3)

      pipe << "x"
      pipe << "y"
      pipe.flush

      pipe.process do
        # should be called twice
      end

      100.times do
        pipe.process do
          raise "pipe is empty should not happen"
        end
      end
    end

    it "can correctly process incoming messages on pipe" do
      pipe = new_pipe(3, processor: DropSeconds.new)
      pipe << "a"
      pipe << "b"
      pipe << "c"
      pipe << "d"

      pipe.flush

      messages = []
      pipe.process do |message|
        messages << message
      end

      expect(messages).to eq(["a", "c"])
    end

    it "can handle custom reporters" do
      pipe = new_pipe(3, reporter: Doubler.new)
      pipe << "a"
      pipe << "b"

      pipe.flush

      messages = []
      pipe.process do |message|
        messages << message
      end

      expect(messages).to eq(["a", "b", "a", "b"])
    end

    it "correctly chucks out unconsumed messages" do
      pipe = new_pipe(3)
      pipe << "a"
      pipe << "b"
      pipe << "c"
      pipe << "d"

      pipe.flush

      messages = []
      pipe.process do |message|
        messages << message
      end

      expect(messages).to eq(["b", "c", "d"])

    end

  end
end
