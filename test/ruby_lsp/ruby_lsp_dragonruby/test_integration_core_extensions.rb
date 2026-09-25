# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestIntegrationCoreExtensions < Minitest::Test
      include ServerTestHelper

      def test_literal_receiver_offers_numeric_extensions
        with_cursor("def tick(args)\n  5.‸\nend\n") do |server, uri, line, character|
          items = completion_items(server, uri, line, character)
          labels = items.map(&:label)

          assert_includes labels, "seconds"
          assert_includes labels, "frame_index"
          assert_includes labels, "elapsed_time"
          assert_includes labels, "to_sf"
        end
      end

      def test_float_literal_receiver_offers_numeric_extensions
        with_cursor("def tick(args)\n  1.5.‸\nend\n") do |server, uri, line, character|
          assert_includes completion_labels(server, uri, line, character), "seconds"
        end
      end

      def test_core_extension_items_carry_the_dragonruby_label
        with_cursor("def tick(args)\n  5.sec‸\nend\n") do |server, uri, line, character|
          item = completion_items(server, uri, line, character).find { |candidate| candidate.label == "seconds" }

          refute_nil item
          assert_equal "DragonRuby", item.label_details.description
          assert_equal "Integer", item.detail
        end
      end

      def test_standard_ruby_methods_are_not_reoffered
        with_cursor("def tick(args)\n  5.‸\nend\n") do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          refute_includes labels, "clamp"
          refute_includes labels, "fdiv"
          refute_includes labels, "times"
          refute_includes labels, "between?"
        end
      end

      def test_partial_name_filters_core_extensions
        with_cursor("def tick(args)\n  5.fra‸\nend\n") do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "frame"
          assert_includes labels, "frame_index"
          refute_includes labels, "seconds"
        end
      end

      def test_hash_literal_offers_geometry_mixins
        with_cursor("def tick(args)\n  {}.‸\nend\n") do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "intersect_rect?"
          assert_includes labels, "scale_rect"
          assert_includes labels, "rect_center_point"
        end
      end

      def test_array_literal_offers_array_extensions
        with_cursor("def tick(args)\n  [].‸\nend\n") do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "map_2d"
          assert_includes labels, "reject_nil"
          refute_includes labels, "product"
        end
      end

      def test_string_and_symbol_literals_are_typed
        with_cursor("def tick(args)\n  \"\".‸\nend\n") do |server, uri, line, character|
          assert_empty completion_labels(server, uri, line, character)
        end

        with_cursor("def tick(args)\n  :sym.‸\nend\n") do |server, uri, line, character|
          assert_empty completion_labels(server, uri, line, character)
        end
      end

      def test_core_extensions_apply_to_registry_core_returns
        with_cursor("def tick(args)\n  args.inputs.keyboard.active.‸\nend\n") do |server, uri, line, character|
          assert_includes completion_labels(server, uri, line, character), "seconds"
        end
      end

      def test_core_extensions_apply_to_state_values_with_inferred_types
        source = "def tick(args)\n  args.state.player ||= { x: 0 }\n  args.state.player.‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          items = completion_items(server, uri, line, character)
          labels = items.map(&:label)

          assert_includes labels, "intersect_rect?"
          assert_includes labels, "scale_rect"
          assert_includes items.select { |item| item.label == "intersect_rect?" }
            .map { |item| item.label_details.description },
            "DragonRuby"
        end
      end

      def test_state_value_hover_shows_the_extension_doc
        source = "def tick(args)\n  args.state.player ||= { x: 0 }\n  args.state.player.intersect_re‸ct?(:other)\nend\n"
        with_cursor(source) do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content, "intersect_rect?"
          assert_includes content, "DragonRuby extension of `Hash`."
        end
      end

      def test_constant_root_offers_class_scope_extensions
        with_cursor("Numeric.‸\n") do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "frame_index"
          assert_includes labels, "compose_blendmode"
          assert_includes labels, "rand"
          refute_includes labels, "seconds"
        end
      end

      def test_class_scope_array_extensions_are_not_filtered_as_private_kernel_methods
        with_cursor("Array.‸\n") do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "select"
          assert_includes labels, "compact"
          assert_includes labels, "transpose"
        end
      end

      def test_bare_kernel_call_offers_kernel_members
        with_cursor("def tick(args)\n  tick_cou‸\nend\n") do |server, uri, line, character|
          items = completion_items(server, uri, line, character)
          item = items.find { |candidate| candidate.label == "tick_count" }

          refute_nil item
          assert_equal "DragonRuby", item.label_details.description
        end
      end

      def test_bare_kernel_hover_shows_the_extension_doc
        with_cursor("def tick(args)\n  tick_co‸unt\nend\n") do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content, "tick_count"
          assert_includes content, "DragonRuby extension of `Kernel`."
        end
      end

      def test_literal_hover_shows_the_extension_doc
        with_cursor("def tick(args)\n  5.frame_‸index\nend\n") do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content, "frame_index"
          assert_includes content, "DragonRuby extension of `Integer`."
          assert_includes content, "[DragonRuby docs]"
        end
      end

      def test_unknown_core_extension_member_produces_no_items
        with_cursor("def tick(args)\n  5.no‸pe\nend\n") do |server, uri, line, character|
          assert_empty completion_labels(server, uri, line, character)
          assert_nil hover_content(server, uri, line, character)
        end
      end

      def test_core_extension_completion_on_incomplete_code
        with_cursor("def tick(args)\n  5.‸\nend\n") do |server, uri, line, character|
          refute_empty completion_labels(server, uri, line, character)
        end

        with_cursor("def tick(args)\n  {}.‸\nend\n") do |server, uri, line, character|
          refute_empty completion_labels(server, uri, line, character)
        end
      end
    end
  end
end
