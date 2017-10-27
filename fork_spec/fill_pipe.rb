# writing this by hand cause testing forks in rspec is just going to end up
# making me cry

require 'securerandom'
module DiscoursePrometheus; end

require_relative '../lib/big_pipe'

$pipe = DiscoursePrometheus::BigPipe.new(10)
i = 50

10.times do
  fork do
    1_000_000.times do
      i += 1
      $pipe << "message #{i} #{Process.pid}"
    end
    p "DONE #{Process.pid}"
  end
end

$pipe << "hello"
sleep 30
$pipe << "hello"

$pipe.process do |x|
  p x
end

puts "DONE"
sleep 10
