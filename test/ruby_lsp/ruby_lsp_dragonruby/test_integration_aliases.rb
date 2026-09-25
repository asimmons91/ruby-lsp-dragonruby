# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestIntegrationAliases < Minitest::Test
      include ServerTestHelper

      def test_completion_through_a_local_alias
        source = "def tick(args)\n  kb = args.inputs.keyboard\n  kb.‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "key_down"
          assert_includes labels, "space"
        end
      end

      def test_completion_through_chained_aliases
        source = "def tick(args)\n  i = args.inputs\n  kb = i.keyboard\n  kb.‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          assert_includes completion_labels(server, uri, line, character), "key_down"
        end
      end

      def test_reassignment_replaces_the_alias_type
        source = "def tick(args)\n  source = args.inputs\n  source = args.outputs\n  source.‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "sprites"
          refute_includes labels, "keyboard"
        end
      end

      def test_reassignment_to_an_unresolvable_expression_produces_no_add_on_items
        source = "def tick(args)\n  kb = args.inputs.keyboard\n  kb = nil\n  kb.‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          refute_includes labels, "key_down"
          refute_includes labels, "space"
        end
      end

      def test_assignments_inside_conditionals_count
        source = <<~RUBY
          def tick(args)
            if args.state.foo
              kb = args.inputs.keyboard
            end
            kb.key_d‸
          end
        RUBY
        with_cursor(source) do |server, uri, line, character|
          assert_includes completion_labels(server, uri, line, character), "key_down"
        end
      end

      def test_block_local_alias_does_not_leak_out
        source = "def tick(args)\n  [1].each { kb = args.inputs.keyboard }\n  kb.‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          refute_includes labels, "key_down"
          refute_includes labels, "space"
        end
      end

      def test_block_sees_an_enclosing_alias
        source = "def tick(args)\n  kb = args.inputs.keyboard\n  [1].each { kb.‸ }\nend\n"
        with_cursor(source) do |server, uri, line, character|
          assert_includes completion_labels(server, uri, line, character), "key_down"
        end
      end

      def test_block_parameter_shadows_an_outer_alias
        source = "def tick(args)\n  kb = args.inputs.keyboard\n  [1].each { |kb| kb.‸ }\nend\n"
        with_cursor(source) do |server, uri, line, character|
          refute_includes completion_labels(server, uri, line, character), "key_down"
        end
      end

      def test_half_typed_member_through_an_alias
        source = "def tick(args)\n  kb = args.inputs.keyboard\n  kb.key_d‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "key_down"
          refute_includes labels, "key_up"
        end
      end

      def test_unclosed_hash_through_an_alias_offers_schema_keys
        source = "def tick(args)\n  sprites = args.outputs.sprites\n  sprites << { x: 0,‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "y"
          assert_includes labels, "path"
          refute_includes labels, "x"
        end
      end

      def test_primitive_context_after_primitives_are_reassigned
        source = <<~RUBY
          def tick(args)
            collection = args.outputs.labels
            collection = args.outputs.sprites
            collection << {‸
          end
        RUBY
        with_cursor(source) do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "path"
          refute_includes labels, "text"
        end
      end

      def test_member_hover_through_an_alias
        source = "def tick(args)\n  kb = args.inputs.keyboard\n  kb.key_do‸wn\nend\n"
        with_cursor(source) do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content, "key_down → GTK::KeyboardKeys"
          assert_includes content, "Keys pressed on this frame only."
        end
      end

      def test_primitive_key_hover_through_an_alias
        source = <<~RUBY
          def tick(args)
            sprites = args.outputs.sprites
            sprites << { x‸: 0 }
          end
        RUBY
        with_cursor(source) do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content, "x → Numeric"
          assert_includes content, "X position."
        end
      end

      # Known limitation from M0-S1 and M4: Ruby LSP does not select local
      # variables as hover targets, so halting on a bare alias never reaches
      # add-on listeners in the pinned range.
      def test_bare_alias_hover_is_not_reachable
        source = "def tick(args)\n  kb = args.inputs.keyboard\n  k‸b\nend\n"
        with_cursor(source) do |server, uri, line, character|
          assert_nil hover_content(server, uri, line, character)
        end
      end
    end
  end
end
