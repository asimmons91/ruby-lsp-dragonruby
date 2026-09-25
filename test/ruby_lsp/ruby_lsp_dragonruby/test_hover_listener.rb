# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestHoverListener < Minitest::Test
      include RegistryTestHelper

      def setup
        @registry = load_registry(files_with_runtime)
        @logger = quiet_logger
        @builder = ResponseBuilders::Hover.new
        @dispatcher = Prism::Dispatcher.new
        @listener = Listeners::Hover.new(@builder, @registry, nil, @dispatcher, logger: @logger)
      end

      def test_member_hover_shows_signature_return_and_doc
        dispatch_hover("def tick(args)\n  args.inputs.keyboard\nend\n")
        content = @builder.response

        assert_includes content, "keyboard → GTK::Keyboard"
        assert_includes content, "Keyboard"
      end

      def test_method_hover_shows_parameters
        dispatch_hover("def tick(args)\n  args.inputs.keyboard.key_down.key_down?\nend\n")
        content = @builder.response

        assert_includes content, "key_down?(key, repeat:, &block) → Boolean"
        assert_includes content, "Checks a key"
      end

      def test_alias_hover_resolves_to_its_member
        dispatch_hover("def tick(args)\n  args.inputs.keyboard.bee\nend\n")
        content = @builder.response

        assert_includes content, "b → Boolean"
        assert_includes content, "The b key"
      end

      def test_global_root_hover
        dispatch_hover("$gtk\n")
        content = @builder.response

        assert_includes content, "$gtk → GTK::Runtime"
        assert_includes content, "The runtime"
      end

      def test_global_root_hover_with_curated_type_doc
        dispatch_hover("$args\n")
        content = @builder.response

        assert_includes content, "$args → GTK::Args"
        assert_includes content, "Root object"
      end

      def test_constant_root_hover
        dispatch_hover("GTK::Args\n")
        content = @builder.response

        assert_includes content, "GTK::Args → GTK::Args"
      end

      def test_local_variable_root_hover
        node = Prism.parse("def tick(args)\n  args.inputs\nend").value.statements.body.first.body.body.first.receiver
        @dispatcher.dispatch_once(node)
        content = @builder.response

        assert_includes content, "args → GTK::Args"
        assert_includes content, "Root object"
      end

      def test_docs_url_is_linked_last
        dispatch_hover("$gtk.args\n")
        content = @builder.response

        assert_includes content, "args → GTK::Args"
        assert content.end_with?("[DragonRuby docs](https://docs.dragonruby.org/#/api/runtime)")
      end

      def test_unknown_member_produces_nothing
        dispatch_hover("def tick(args)\n  args.nope\nend\n")

        assert_predicate @builder, :empty?
      end

      def test_unknown_root_produces_nothing
        dispatch_hover("$stdout\n")

        assert_predicate @builder, :empty?
      end

      def test_errors_are_logged_and_isolated
        resolver = @listener.instance_variable_get(:@resolver)

        resolver.stub(:resolve, ->(*) { raise "boom" }) do
          dispatch_hover("def tick(args)\n  args.inputs.keyboard\nend\n")
        end

        assert(@logger.messages.any? { |message| message.include?("boom") })
      end

      private

      def dispatch_hover(source)
        statements = Prism.parse(source).value.statements.body
        first = statements.first
        node = first.is_a?(Prism::DefNode) ? first.body.body.first : statements.first
        @dispatcher.dispatch_once(node)
      end
    end
  end
end
