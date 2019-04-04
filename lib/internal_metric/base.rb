# frozen_string_literal: true

module DiscoursePrometheus::InternalMetric
  class Base

    def self.attribute(*names)
      (@attrs ||= []).concat(names)
      attr_accessor(*names)
    end

    def self.attributes
      @attrs
    end

    def self.from_h(hash)
      klass =
        case (hash["_type"] || hash[:_type])
        when "Job"
          Job
        when "Global"
          Global
        when "Web"
          Web
        when "Process"
          Process
        when "Custom"
          Custom
        else
          raise "class deserialization not implemented"
        end
      instance = klass.new
      instance.from_h(hash)
      instance
    end

    def from_h(hash)
      hash.each do |k, v|
        next if k == "_type" || k == :_type
        self.send "#{k}=", v
      end
      self
    end

    def to_json(*ignore)
      Oj.dump(to_h)
    end

    def to_h
      hash = Hash[
        *self.class.attributes.map { |a| [a, send(a)] }.flatten
      ]

      # for perf, this is called alot
      type =
        case self
        when Job
          "Job"
        when Global
          "Global"
        when Web
          "Web"
        when Process
          "Process"
        when Custom
          "Custom"
        else
          raise "not implemented"
        end

      hash[:_type] = type
      hash
    end

  end
end
