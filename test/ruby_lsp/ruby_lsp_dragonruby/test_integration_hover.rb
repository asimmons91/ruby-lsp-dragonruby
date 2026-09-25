# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestIntegrationHover < Minitest::Test
      include ServerTestHelper

      def test_member_hover
        with_cursor("def tick(args)\n  args.inputs.keybo‸ard\nend\n") do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content, "keyboard → GTK::Keyboard"
          assert_includes content, "Keyboard state"
        end
      end

      def test_global_root_hover
        with_cursor("$gt‸k\n") do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content, "$gtk → GTK::Runtime"
          assert_includes content, "The DragonRuby runtime"
        end
      end

      def test_constant_root_hover
        with_cursor("Geom‸etry\n") do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content, "Geometry → Geometry"
        end
      end

      def test_member_hover_includes_docs_link
        with_cursor("def tick(args)\n  args.inp‸uts.keyboard\nend\n") do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content, "inputs → GTK::Inputs"
          assert_includes content, "[DragonRuby docs](https://docs.dragonruby.org/#/api/inputs)"
        end
      end

      def test_trailing_dot_hover_is_robust
        with_cursor("def tick(args)\n  args.inputs.keyboard.‸\nend\n") do |server, uri, line, character|
          refute_match(/keyboard →/, hover_content(server, uri, line, character).to_s)
        end
      end

      # Known limitation from M0-S1: Ruby LSP does not select local variables
      # as hover targets, so add-ons never see the `args` parameter.
      def test_args_parameter_hover_is_not_reachable
        with_cursor("def tick(ar‸gs)\n  args.inputs\nend\n") do |server, uri, line, character|
          assert_nil hover_content(server, uri, line, character)
        end
      end
    end
  end
end
