require 'rails_helper'

module DiscoursePrometheus
  describe BigPipe do
    after do
      @pipe.destroy! if @pipe
    end

    def new_pipe(size)
      @pipe.destroy! if @pipe
      @pipe = BigPipe.new(size)
    end

    it "correctly chucks out unconsumed messages" do
      pipe = new_pipe(3)
      pipe << "a"
      pipe << "b"
      pipe << "c"
      pipe << "d"

      messages = []
      pipe.process do |message|
        messages << message
      end

      expect(messages).to eq(["b", "c", "d"])

    end

  end
end
