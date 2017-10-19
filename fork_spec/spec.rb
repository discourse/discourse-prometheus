# writing this by hand cause testing forks in rspec is just going to end up
# making me cry

require 'securerandom'
module DiscoursePrometheus; end

require_relative '../lib/big_pipe'

$pipe = DiscoursePrometheus::BigPipe.new(3)

5.times do
  fork do
    begin
      100.times do
        $pipe << "100"
      end
    rescue => e
      p e
    end
    exit
  end

  fork do
    100.times do
      $pipe << "200"
    end
    exit
  end

  fork do
    $pipe.process do |message|
      puts message
    end

    exit
  end
  sleep 0.1
end
