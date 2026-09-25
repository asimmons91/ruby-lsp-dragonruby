# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestIndexingEnhancement < Minitest::Test
      include RegistryTestHelper

      TAG = "<!-- dragonruby:attr_gtk -->"

      def setup
        @registry = load_registry(valid_files)
        @index = RubyIndexer::Index.new
        IndexingEnhancement.registry = @registry
      end

      def teardown
        IndexingEnhancement.registry = nil
      end

      def test_attr_gtk_registers_tagged_accessors
        index("class Game\n  attr_gtk\nend\n")

        inputs = @index.method_completion_candidates("inputs", "Game")
        assert_equal ["inputs"], inputs.map(&:name)
        assert_includes inputs.first.comments, TAG
        assert_includes inputs.first.comments, "The inputs"
      end

      def test_attr_dr_alias_is_recognized
        index("class Game\n  attr_dr\nend\n")

        refute_empty @index.method_completion_candidates("state", "Game")
      end

      def test_attr_sprite_expands_schema_keys
        index("class Player\n  attr_sprite\nend\n")

        assert_equal ["w"], @index.method_completion_candidates("w", "Player").map(&:name)
        refute_empty @index.method_completion_candidates("blend_mode_enum", "Player")
        assert_empty @index.method_completion_candidates("__dragonruby_attr_sprite", "Player")
      end

      def test_subclasses_inherit_tagged_accessors
        index("class Base\n  attr_gtk\nend\nclass Child < Base\nend\n")
        context = Struct.new(:nesting).new(["Child"])

        assert MacroLookup.applied?(@index, @registry.macro("attr_gtk"), context)
      end

      def test_unconfigured_enhancement_is_inert
        IndexingEnhancement.registry = nil
        index("class Game\n  attr_gtk\nend\n")

        assert_empty @index.method_completion_candidates("inputs", "Game")
      end

      def test_calls_with_a_receiver_are_ignored
        index("class Game\n  self.attr_gtk\nend\n")
        context = Struct.new(:nesting).new(["Game"])

        refute MacroLookup.applied?(@index, @registry.macro("attr_gtk"), context)
      end

      private

      def index(source)
        result = Prism.parse(source)
        dispatcher = Prism::Dispatcher.new
        RubyIndexer::DeclarationListener.new(@index, dispatcher, result, URI("file:///test.rb"))
        dispatcher.dispatch(result.value)
      end
    end
  end
end
