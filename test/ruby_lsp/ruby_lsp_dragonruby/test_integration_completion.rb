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

      def test_unclosed_hash_does_not_produce_add_on_items_or_raise
        with_cursor("def tick(args)\n  args.outputs.sprites << { x: 0,‸\nend\n") do |server, uri, line, character|
          assert_empty completion_labels(server, uri, line, character)
        end
      end

      def test_missing_value_does_not_produce_add_on_items_or_raise
        with_cursor("def tick(args)\n  args.outputs.primitives << { x:‸\nend\n") do |server, uri, line, character|
          assert_empty completion_labels(server, uri, line, character)
        end
      end
    end
  end
end
