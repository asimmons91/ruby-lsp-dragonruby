# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestHoverListener < Minitest::Test
      include RegistryTestHelper
      include NodeContextHelper

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

      def test_primitive_key_hover_shows_type_default_and_doc
        content = primitive_hover("def tick(args)\n  args.outputs.sprites << { x‸: 0 }\nend\n")

        assert_includes content, "x → Numeric"
        assert_includes content, "X"
      end

      def test_primitive_key_hover_shows_allowed_values
        content = primitive_hover("def tick(args)\n  args.outputs.sprites << { blend_mode_enum‸: 0 }\nend\n")

        assert_includes content, "Default: 0"
        assert_includes content, "Allowed values: 0, 1"
      end

      def test_primitive_value_hover_produces_nothing
        content = primitive_hover("def tick(args)\n  args.outputs.sprites << { x: :nop‸e }\nend\n")

        assert_empty content.to_s
      end

      def test_primitive_key_hover_outside_a_context_produces_nothing
        content = primitive_hover("x = { x‸: 0 }\n")

        assert_empty content.to_s
      end

      def test_attr_gtk_accessor_hover
        content = macro_hover("class Game\n  attr_gtk\n  def tick\n    inp‸uts\n  end\nend\n")

        assert_includes content, "inputs → GTK::Inputs"
        assert_includes content, "The inputs"
        assert_includes content, "Provided by `attr_gtk`."
      end

      def test_attr_sprite_accessor_hover
        content = macro_hover("class Player\n  attr_sprite\n  def tick\n    sel‸f.w\n  end\nend\n")

        assert_includes content, "w → Numeric"
        assert_includes content, "Provided by `attr_sprite`."
      end

      def test_macro_accessor_hover_without_the_macro_produces_nothing
        content = macro_hover("class Game\n  def tick\n    inp‸uts\n  end\nend\n")

        assert_empty content.to_s
      end

      def test_macro_accessor_hover_prefers_the_applied_macro
        source = "class Game\n  attr_other\n  def tick\n    arg‸s\n  end\nend\n"
        content = macro_hover(source, files: valid_files.merge("macros.yml" => SHARED_MACROS))

        assert_includes content, "args → GTK::Inputs"
        refute_includes content, "args → GTK::Args"
      end

      private

      def dispatch_hover(source)
        statements = Prism.parse(source).value.statements.body
        first = statements.first
        node = first.is_a?(Prism::DefNode) ? first.body.body.first : statements.first
        @dispatcher.dispatch_once(node)
      end

      def primitive_hover(source)
        builder = ResponseBuilders::Hover.new
        dispatcher = Prism::Dispatcher.new
        context = locate_context(
          source,
          adjust: 0,
          node_types: RubyLsp::Listeners::Hover::ALLOWED_TARGETS
        )
        Listeners::Hover.new(builder, load_primitive_registry, context, dispatcher, logger: @logger)
        dispatcher.dispatch_once(context.node) if context.node
        builder.response
      end

      def macro_hover(source, files: valid_files)
        registry = load_registry(files)
        index = RubyIndexer::Index.new
        IndexingEnhancement.registry = registry

        clean = source.delete(CURSOR)
        context = locate_context(
          source,
          adjust: 0,
          node_types: RubyLsp::Listeners::Hover::ALLOWED_TARGETS
        )
        index.index_single(URI("file:///test.rb"), clean)

        builder = ResponseBuilders::Hover.new
        dispatcher = Prism::Dispatcher.new
        Listeners::Hover.new(builder, registry, context, dispatcher, logger: @logger, index: index)
        dispatcher.dispatch_once(context.node) if context.node
        builder.response
      ensure
        IndexingEnhancement.registry = nil
      end
    end
  end
end
