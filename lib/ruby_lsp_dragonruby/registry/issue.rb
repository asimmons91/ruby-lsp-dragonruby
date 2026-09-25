# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      class Issue
        attr_reader :path, :message, :severity

        def initialize(path:, message:, severity: :error)
          @path = path
          @message = message
          @severity = severity
          freeze
        end

        def error?
          @severity == :error
        end

        def warning?
          @severity == :warning
        end

        def to_s
          "#{@path}: #{@message}"
        end
      end
    end
  end
end
