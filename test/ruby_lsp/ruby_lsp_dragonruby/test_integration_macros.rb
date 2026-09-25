# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestIntegrationMacros < Minitest::Test
      include ServerTestHelper

      def test_attr_sprite_registers_accessors_for_completion
        source = "class Player\n  attr_sprite\n\n  def tick\n    self.‸\n  end\nend\n"
        with_cursor(source) do |server, uri, line, character|
          reindex(server, uri, source)
          labels = completion_labels(server, uri, line, character, trigger_character: ".")

          assert_includes labels, "x"
          assert_includes labels, "path"
          assert_includes labels, "blendmode_enum"
          refute_includes labels, "__dragonruby_attr_sprite"
        end
      end

      def test_attr_sprite_accessor_hover
        source = "class Player\n  attr_sprite\n\n  def tick\n    self.pa‸th\n  end\nend\n"
        with_cursor(source) do |server, uri, line, character|
          reindex(server, uri, source)
          content = hover_content(server, uri, line, character)

          assert_includes content, "path → String | Symbol"
          assert_includes content, "Provided by `attr_sprite`."
        end
      end

      def test_attr_gtk_accessor_completion_matches_args_members
        source = "class Game\n  attr_gtk\n\n  def tick\n    outputs.‸\n  end\nend\n"
        with_cursor(source) do |server, uri, line, character|
          reindex(server, uri, source)
          labels = completion_labels(server, uri, line, character, trigger_character: ".")

          assert_includes labels, "sprites"
          assert_includes labels, "labels"
          assert_includes labels, "background_color"
        end
      end

      def test_attr_gtk_receiverless_chain_completion
        source = "class Game\n  attr_gtk\n\n  def tick\n    inputs.keyboard.‸\n  end\nend\n"
        with_cursor(source) do |server, uri, line, character|
          reindex(server, uri, source)
          labels = completion_labels(server, uri, line, character, trigger_character: ".")

          assert_includes labels, "space"
          assert_includes labels, "key_down"
        end
      end

      def test_attr_gtk_primitive_context
        source = "class Game\n  attr_gtk\n\n  def tick\n    outputs.sprites << {‸\n  end\nend\n"
        with_cursor(source) do |server, uri, line, character|
          reindex(server, uri, source)
          assert_includes completion_labels(server, uri, line, character), "path"
        end
      end

      def test_attr_gtk_subclass_resolves_accessors
        source = <<~RUBY
          class Base
            attr_gtk
          end

          class Child < Base
            def tick
              state.‸
            end
          end
        RUBY
        with_cursor(source) do |server, uri, line, character|
          reindex(server, uri, source)
          labels = completion_labels(server, uri, line, character, trigger_character: ".")

          assert_includes labels, "new_entity"
          assert_includes labels, "entity_id"
        end
      end

      def test_class_without_attr_gtk_gets_no_add_on_items
        source = "class Game\n  def tick\n    outputs.‸\n  end\nend\n"
        with_cursor(source) do |server, uri, line, character|
          reindex(server, uri, source)

          assert_empty completion_labels(server, uri, line, character, trigger_character: ".")
        end
      end

      def test_attr_gtk_accessor_hover
        source = "class Game\n  attr_gtk\n\n  def tick\n    out‸puts\n  end\nend\n"
        with_cursor(source) do |server, uri, line, character|
          reindex(server, uri, source)
          content = hover_content(server, uri, line, character)

          assert_includes content, "outputs → GTK::Outputs"
          assert_includes content, "Provided by `attr_gtk`."
        end
      end
    end
  end
end
