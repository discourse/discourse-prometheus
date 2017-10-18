class ::DiscoursePrometheus::Metric

  FLOAT_ATTRS = %w{
    duration
    sql_duration
    redis_duration
  }

  INT_ATTRS = %w{
    sql_calls
    redis_calls
    status_code
  }

  BOOL_ATTRS = %w{
    ajax
    background
    logged_in
    crawler
    mobile
    tracked
  }

  STRING_ATTRS = %w{
    controller
    action
  }

  (FLOAT_ATTRS + INT_ATTRS + BOOL_ATTRS + STRING_ATTRS).each do |attr|
    attr_accessor attr
  end

  # optimized to keep collecting as cheap as possible
  class_eval <<~RUBY
    def to_s
      str = String.new
      #{FLOAT_ATTRS.map { |f| "str << #{f}.to_f.round(4).to_s" }.join("\nstr << \" \"\n")}
      str << " "
      #{INT_ATTRS.map { |f| "str << #{f}.to_i.to_s" }.join("\nstr << \" \"\n")}
      str << " "
      #{BOOL_ATTRS.map { |f| "str << (#{f} || false ? 't' : 'f')" }.join("\nstr << \" \"\n")}
      str << " "
      #{STRING_ATTRS.map { |f| "str << #{f}.to_s" }.join("\nstr << \" \"\n")}
    end
  RUBY

  def self.parse(str)
    result = self.new

    split = str.split(' ')

    i = 0

    FLOAT_ATTRS.each do |attr|
      result.send "#{attr}=", split[i].to_f
      i += 1
    end

    INT_ATTRS.each do |attr|
      result.send "#{attr}=", split[i].to_i
      i += 1
    end

    BOOL_ATTRS.each do |attr|
      result.send "#{attr}=", split[i] == 't'
      i += 1
    end

    STRING_ATTRS.each do |attr|
      result.send "#{attr}=", split[i].to_s
      i += 1
    end
    result
  end

  def self.from_env_data(env, data)
    metric = self.new

    if ad_params = env['action_dispatch.request.parameters']
      metric.controller = ad_params['controller']
      metric.action = ad_params['action']
    end

    if timing = data[:timing]
      metric.duration = timing[:duration]
      metric.sql_duration = timing[:sql][:duration]
      metric.redis_duration = timing[:redis][:duration]
      metric.sql_calls = timing[:sql][:calls]
      metric.redis_calls = timing[:redis][:calls]
    end

    metric.status_code = data[:status].to_i
    metric.crawler = !!data[:is_crawler]
    metric.logged_in = !!data[:has_auth_cookie]
    metric.background = !!data[:is_background]
    metric.mobile = !!data[:is_mobile]
    metric.tracked = !!data[:track_view]

    metric
  end
end
