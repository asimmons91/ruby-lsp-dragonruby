# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestCompletionListener < Minitest::Test
      include RegistryTestHelper
      include NodeContextHelper

      def setup
        @registry = load_registry(files_with_runtime)
        @logger = quiet_logger
        @builder = ResponseBuilders::CollectionResponseBuilder.new
        @dispatcher = Prism::Dispatcher.new
        @listener = Listeners::Completion.new(
          @builder,
          @registry,
          nil,
          @dispatcher,
          URI("file:///test.rb"),
          logger: @logger
        )
      end

      def test_trailing_dot_offers_members_including_parents
        items = dispatch("def tick(args)\n  args.inputs.\nend\n")

        assert_equal %w[base keyboard], items.map(&:label).sort
      end

      def test_partial_name_filters_members
        items = dispatch("def tick(args)\n  args.inputs.ke\nend\n")

        assert_equal ["keyboard"], items.map(&:label)
      end

      def test_multiline_continuation_filters_by_the_typed_name
        items = dispatch("def tick(args)\n  args.inputs.\n  keybo\nend\n")

        assert_equal ["keyboard"], items.map(&:label)
        range = items.first.text_edit.range
        assert_equal 2, range.start.line
        assert_equal 2, range.start.character
        assert_equal 7, range.end.character
      end

      def test_generated_and_aliased_members_are_offered
        labels = dispatch("def tick(args)\n  args.inputs.keyboard.\nend\n").map(&:label)

        %w[a b bee key_down].each { |label| assert_includes labels, label }
      end

      def test_global_root_completion
        labels = dispatch("$gtk.\n").map(&:label)

        assert_equal ["args"], labels
      end

      def test_safe_navigation_trailing_dot
        labels = dispatch("def tick(args)\n  args&.inputs&.\nend\n").map(&:label)

        assert_equal %w[base keyboard], labels.sort
      end

      def test_unknown_root_produces_no_items
        assert_empty dispatch("foo.bar.\n")
      end

      def test_missing_member_produces_no_items
        assert_empty dispatch("def tick(args)\n  args.nope.\nend\n")
      end

      def test_does_not_duplicate_labels_already_in_the_response
        @builder << Interface::CompletionItem.new(label: "base")
        items = dispatch("def tick(args)\n  args.inputs.\nend\n")

        assert_equal 2, items.size
        assert_equal 1, items.count { |item| item.label == "base" }
        assert_includes items.map(&:label), "keyboard"
      end

      def test_item_shape_matches_requirement
        item = dispatch("def tick(args)\n  args.inputs.ke\nend\n").first

        assert_equal "keyboard", item.label
        assert_equal Constant::CompletionItemKind::PROPERTY, item.kind
        assert_equal "GTK::Keyboard", item.detail
        assert_equal "DragonRuby", item.label_details.description
        assert_includes item.documentation.value, "Keyboard"
        assert_equal 1, item.text_edit.range.start.line
        assert_equal 14, item.text_edit.range.start.character
        assert_equal 16, item.text_edit.range.end.character
      end

      def test_trailing_dot_text_edit_is_zero_width_after_the_operator
        item = dispatch("def tick(args)\n  args.inputs.\nend\n").first
        range = item.text_edit.range

        assert_equal 1, range.start.line
        assert_equal range.start.character, range.end.character
      end

      def test_errors_are_logged_and_isolated
        resolver = @listener.instance_variable_get(:@resolver)

        resolver.stub(:resolve, ->(*) { raise "boom" }) do
          dispatch("def tick(args)\n  args.inputs.\nend\n")
        end

        assert(@logger.messages.any? { |message| message.include?("boom") })
      end

      def test_primitive_key_completion_excludes_existing_keys
        items = dispatch_primitive("def tick(args)\n  args.outputs.sprites << { x: 0,‸\nend\n")

        labels = items.map(&:label)
        assert_includes labels, "y"
        refute_includes labels, "x"
      end

      def test_primitive_key_item_shape
        item = dispatch_primitive("def tick(args)\n  args.outputs.sprites << { x: 0,‸\nend\n").find { |i| i.label == "y" }

        assert_equal Constant::CompletionItemKind::FIELD, item.kind
        assert_equal "Numeric", item.detail
        assert_equal "y: ", item.text_edit.new_text
        assert_equal "sprite", item.label_details.description
      end

      def test_primitive_partial_key_filters_by_typed_name
        items = dispatch_primitive("def tick(args)\n  args.outputs.sprites << { x: 0, pa‸\nend\n")

        assert_equal ["path"], items.map(&:label)
        assert_equal 1, items.first.text_edit.range.start.line
      end

      def test_primitive_value_completion_offers_allowed_values
        items = dispatch_primitive("def tick(args)\n  args.outputs.labels << { x: 0, alignment_enum:‸\nend\n")

        assert_equal %w[0 1 2], items.map(&:label)
        assert_equal Constant::CompletionItemKind::ENUM_MEMBER, items.first.kind
      end

      def test_generic_collection_restricts_keys_by_primitive_marker
        items = dispatch_primitive("def tick(args)\n  args.outputs.primitives << { primitive_marker: :label,‸\nend\n")

        labels = items.map(&:label)
        assert_includes labels, "text"
        refute_includes labels, "path"
      end

      def test_generic_collection_offers_primitive_marker_key
        items = dispatch_primitive("def tick(args)\n  args.outputs.primitives << {‸\nend\n")

        assert_includes items.map(&:label), "primitive_marker"
      end

      def test_generic_collection_marker_value_completion
        items = dispatch_primitive("def tick(args)\n  args.outputs.primitives << { primitive_marker:‸\nend\n")

        assert_equal %w[:sprite :label], items.map(&:label)
      end

      def test_array_of_hashes_is_a_primitive_context
        items = dispatch_primitive("def tick(args)\n  args.outputs.labels << [{‸\nend\n")

        assert_includes items.map(&:label), "text"
      end

      def test_push_is_a_primitive_context
        items = dispatch_primitive("def tick(args)\n  args.outputs.sprites.push({‸\nend\n")

        assert_includes items.map(&:label), "path"
      end

      def test_concat_is_a_primitive_context
        items = dispatch_primitive("def tick(args)\n  args.outputs.labels.concat([{‸\nend\n")

        assert_includes items.map(&:label), "text"
      end

      def test_chain_completion_in_append_argument_still_works
        items = dispatch_primitive("def tick(args)\n  args.outputs.sprites << args.outputs.‸\nend\n")

        assert_includes items.map(&:label), "labels"
      end

      def test_chain_completion_inside_a_key_without_allowed_values
        items = dispatch_primitive("def tick(args)\n  args.outputs.sprites << { path: args.outputs.‸ }\nend\n")

        assert_includes items.map(&:label), "labels"
      end

      def test_union_key_detail_marks_each_schema
        item = dispatch_primitive("def tick(args)\n  args.outputs.primitives << {‸\nend\n").find { |i| i.label == "x" }

        assert_equal "Numeric (sprite, label)", item.detail
      end

      def test_non_primitive_hash_gets_no_key_completions
        items = dispatch_primitive("x = { x: 0, ‸\n")

        assert_empty items
      end

      def test_unknown_root_primitive_context_gets_no_completions
        items = dispatch_primitive("foo << { ‸\n")

        assert_empty items
      end

      def test_argument_key_value_offers_no_values_without_allowed_values
        items = dispatch_primitive("def tick(args)\n  args.outputs.sprites << { x: 0, y:‸\nend\n")

        assert_empty items
      end

      private

      def dispatch(source)
        statements = Prism.parse(source).value.statements.body
        first = statements.first
        node = first.is_a?(Prism::DefNode) ? first.body.body.first : statements.last
        @dispatcher.dispatch_once(node)
        @builder.response
      end

      def dispatch_primitive(source)
        builder = ResponseBuilders::CollectionResponseBuilder.new
        dispatcher = Prism::Dispatcher.new
        context = locate_context(source)
        Listeners::Completion.new(
          builder,
          load_primitive_registry,
          context,
          dispatcher,
          URI("file:///test.rb"),
          logger: @logger
        )
        dispatcher.dispatch_once(context.node) if context.node
        builder.response
      end
    end
  end
end
