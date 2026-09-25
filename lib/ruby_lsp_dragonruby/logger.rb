# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Logger
      attr_reader :messages

      def initialize(io = $stderr)
        @io = io
        @messages = []
      end

      def error(message)
        log(:error, message)
      end

      def warn(message)
        log(:warn, message)
      end

      def debug(message)
        log(:debug, message)
      end

      private

      def log(severity, message)
        entry = "[ruby-lsp-dragonruby] #{severity.to_s.upcase}: #{message}"
        @messages << entry
        @io&.puts(entry)
        nil
      end
    end
  end
end
