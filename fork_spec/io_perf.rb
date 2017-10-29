# 20% slower than directly marshalling to stream, however totally safe to corruption
# on data corruption it will recover

require 'benchmark/ips'

require 'securerandom'
class RobustPipe
  SEP = "\x00\x01\x02"
  REPLACE_SEP = SecureRandom.bytes(16)

  def initialize
    @reader, @writer = IO.pipe
    @reader.binmode
    @writer.binmode

    @buffer = ""
  end

  def <<(data)
    encoded = encode(Marshal.dump(data))
    @writer.syswrite(encoded)
    @writer.syswrite(SEP)
  end

  def read
    while !has_object?
      @buffer << @reader.sysread(10_000)
    end
    next_object
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

@r, @w = IO.pipe
@pipe = RobustPipe.new

Benchmark.ips do |x|

  x.report "unsafe" do |times|
    i = 0
    while i < times
      Marshal.dump("a", @w)
      Marshal.dump("b", @w)
      Marshal.dump("c", @w)
      Marshal.load(@r)
      Marshal.load(@r)
      Marshal.load(@r)
      i += 1
    end
  end

  x.report "safe" do |times|
    i = 0
    while i < times
      @pipe << "a"
      @pipe << "b"
      @pipe << "c"
      @pipe.read
      @pipe.read
      @pipe.read
      i += 1
    end
  end
end

# Warming up --------------------------------------
#               unsafe    10.177k i/100ms
#                 safe     7.856k i/100ms
# Calculating -------------------------------------
#               unsafe    106.742k (± 1.8%) i/s -    539.381k in   5.054798s
#                 safe     82.422k (± 1.8%) i/s -    416.368k in   5.053437s
#
