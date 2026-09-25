# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/ruby_lsp_dragonruby/addon"

module RubyLsp
  module Dragonruby
    class TestAddon < Minitest::Test
      include RegistryTestHelper

      def test_name_and_version
        addon = Addon.new(logger: quiet_logger)
        assert_equal "Ruby LSP DragonRuby", addon.name
        assert_equal VERSION, addon.version
      end

      def test_activation_loads_registry
        addon = Addon.new(logger: quiet_logger)
        called = false
        stub = lambda { |**|
          called = true
          :registry
        }
        Registry.stub(:load, stub) do
          addon.activate(nil, nil)
        end
        assert called
        refute addon.error?
      end

      def test_activation_error_is_isolated
        logger = quiet_logger
        addon = Addon.new(logger: logger)
        Registry.stub(:load, ->(**) { raise "boom" }) do
          addon.activate(nil, nil)
        end
        assert addon.error?
        assert(logger.messages.any? { |message| message.include?("boom") })
      end

      def test_deactivate_resets_registry
        addon = Addon.new(logger: quiet_logger)
        Registry.instance_variable_set(:@default, :sentinel)
        addon.deactivate
        assert_nil Registry.default
      ensure
        Registry.reset!
      end
    end
  end
end
