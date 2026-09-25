# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestIntegrationCompletion < Minitest::Test
      include ServerTestHelper

      def test_keyboard_members_after_trailing_dot
        with_cursor("def tick(args)\n  args.inputs.keyboard.‸\nend\n") do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "key_down"
          assert_includes labels, "key_held"
          assert_includes labels, "space"
          assert_includes labels, "directional_vector"
        end
      end

      def test_render_target_members_after_index_call
        with_cursor("def tick(args)\n  args.outputs[:rt].‸\nend\n") do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "primitives"
          assert_includes labels, "sprites"
          assert_includes labels, "set"
          assert_includes labels, "length"
        end
      end

      def test_partial_name_filters_members
        with_cursor("def tick(args)\n  args.inputs.ke‸\nend\n") do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "keyboard"
          assert_includes labels, "key_down"
          refute_includes labels, "mouse"
        end
      end

      def test_multiline_continuation_filters_by_the_typed_name
        with_cursor("def tick(args)\n  args.inputs.\n  keybo‸\nend\n") do |server, uri, line, character|
          assert_equal ["keyboard"], completion_labels(server, uri, line, character)
        end
      end

      def test_global_root_completion
        with_cursor("$gtk.‸\n") do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "args"
          assert_includes labels, "window_fullscreen?"
        end
      end

      def test_constant_root_completion
        with_cursor("Geometry.‸\n") do |server, uri, line, character|
          assert_includes completion_labels(server, uri, line, character), "angle_to"
        end
      end

      def test_unknown_root_produces_no_add_on_items
        with_cursor("foo.bar.‸\n") do |server, uri, line, character|
          assert_empty completion_labels(server, uri, line, character)
        end
      end

      def test_unclosed_hash_offers_sprite_keys_minus_existing_keys
        with_cursor("def tick(args)\n  args.outputs.sprites << { x: 0,‸\nend\n") do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "y"
          assert_includes labels, "path"
          refute_includes labels, "x"
        end
      end

      # Ruby LSP 0.26 discards completion targets without a parent, so a
      # cursor that sits in trailing whitespace (the common `{ x: 0, |`)
      # never reaches add-on listeners. Completion appears once a key
      # character is typed.
      def test_trailing_whitespace_is_not_a_completion_target
        with_cursor("def tick(args)\n  args.outputs.sprites << { x: 0, ‸\nend\n") do |server, uri, line, character|
          assert_empty completion_labels(server, uri, line, character)
        end
      end

      def test_half_typed_key_filters_schema_keys
        with_cursor("def tick(args)\n  args.outputs.sprites << { x: 0, pa‸\nend\n") do |server, uri, line, character|
          assert_equal ["path"], completion_labels(server, uri, line, character)
        end
      end

      def test_array_of_hashes_offers_label_keys
        with_cursor("def tick(args)\n  args.outputs.labels << [{‸\nend\n") do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "text"
          assert_includes labels, "alignment_enum"
        end
      end

      def test_generic_collection_restricts_keys_by_primitive_marker
        source = "def tick(args)\n  args.outputs.primitives << { primitive_marker: :solid,‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "w"
          refute_includes labels, "text"
        end
      end

      def test_generic_collection_offers_primitive_marker
        with_cursor("def tick(args)\n  args.outputs.primitives << {‸\nend\n") do |server, uri, line, character|
          assert_includes completion_labels(server, uri, line, character), "primitive_marker"
        end
      end

      def test_allowed_values_are_offered_at_the_value_position
        with_cursor("def tick(args)\n  args.outputs.labels << { x: 0, alignment_enum:‸\nend\n") do |server, uri, line, character|
          assert_equal %w[0 1 2], completion_labels(server, uri, line, character)
        end
      end

      def test_missing_value_without_allowed_values_produces_no_items
        with_cursor("def tick(args)\n  args.outputs.primitives << { x:‸\nend\n") do |server, uri, line, character|
          assert_empty completion_labels(server, uri, line, character)
        end
      end

      def test_non_primitive_hash_gets_no_key_completions
        with_cursor("x = { x: 0, ‸\n") do |server, uri, line, character|
          assert_empty completion_labels(server, uri, line, character)
        end
      end

      def test_unknown_collection_gets_no_key_completions
        with_cursor("foo << { ‸\n") do |server, uri, line, character|
          assert_empty completion_labels(server, uri, line, character)
        end
      end
    end
  end
end
