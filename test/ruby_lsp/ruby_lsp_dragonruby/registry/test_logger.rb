# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestLogger < Minitest::Test
      include RegistryTestHelper

      def test_records_and_writes_messages
        io = StringIO.new
        logger = Logger.new(io)
        logger.warn("careful")
        logger.error("broken")

        assert_equal 2, logger.messages.size
        assert_includes logger.messages[0], "WARN: careful"
        assert_includes logger.messages[1], "ERROR: broken"
        assert_includes io.string, "ERROR: broken"
      end

      def test_accepts_nil_io
        logger = Logger.new(nil)
        logger.error("quiet")
        assert_equal ["[ruby-lsp-dragonruby] ERROR: quiet"], logger.messages
      end
    end
  end
end
