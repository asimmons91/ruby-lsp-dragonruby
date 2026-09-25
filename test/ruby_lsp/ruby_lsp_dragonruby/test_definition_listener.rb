# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestDefinitionListener < Minitest::Test
      include RegistryTestHelper
      include NodeContextHelper

      def setup
        @registry = load_registry(valid_files)
        @logger = quiet_logger
        @tracker = StateTracker.new(@registry, logger: @logger)
      end

      def test_definition_returns_every_write_site_initializations_first
        @tracker.replace_source(URI("file:///a.rb"),
          "def tick(args)\n  args.state.player.x = 1\n  args.state.player.x ||= 0\nend\n")
        @tracker.replace_source(URI("file:///b.rb"),
          "def tick(args)\n  args.state.player.x ||= 2\nend\n")

        locations = dispatch_definition("def tick(args)\n  args.state.player.‸x\nend\n")

        assert_equal ["file:///a.rb", "file:///b.rb", "file:///a.rb"], locations.map(&:uri)
        assert_equal [2, 1, 1], locations.map { |location| location.range.start.line }
      end

      def test_definition_for_an_intermediate_path_points_at_nested_writes
        @tracker.replace_source(URI("file:///a.rb"), "def tick(args)\n  args.state.player.x ||= 0\nend\n")

        locations = dispatch_definition("def tick(args)\n  args.state.play‸er\nend\n")

        assert_equal 1, locations.size
        assert_equal 1, locations.first.range.start.line
      end

      def test_definition_for_an_unknown_path_returns_nothing
        locations = dispatch_definition("def tick(args)\n  args.state.player.‸x\nend\n")

        assert_empty locations
      end

      def test_definition_for_a_member_call_returns_nothing
        @tracker.replace_source(URI("file:///a.rb"), "def tick(args)\n  args.state.player.x ||= 0\nend\n")

        locations = dispatch_definition("def tick(args)\n  args.state.player.inside_re‸ct?(:r)\nend\n")

        assert_empty locations
      end

      private

      def dispatch_definition(source)
        builder = ResponseBuilders::CollectionResponseBuilder.new
        dispatcher = Prism::Dispatcher.new
        context = locate_context(source, adjust: 0)
        Listeners::Definition.new(
          builder,
          @registry,
          context,
          dispatcher,
          URI("file:///test.rb"),
          logger: @logger,
          state: @tracker
        )
        dispatcher.dispatch_once(context.node) if context.node
        builder.response
      end
    end
  end
end
