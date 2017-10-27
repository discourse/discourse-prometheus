# writing this by hand cause testing forks in rspec is just going to end up
# making me cry

require 'securerandom'
module DiscoursePrometheus; end

require_relative '../lib/big_pipe'

$pipe = DiscoursePrometheus::BigPipe.new(10)
i = 500

10.times do
  fork do
    10_000.times do
      i += 1
      $pipe << "message #{i} #{Process.pid}"
    end
    $pipe.flush
  end
end

sleep 5

$pipe << "hello"
$pipe << "hello"
$pipe.flush

$pipe.process do |x|
  p x
end

puts "DONE"
sleep 10
