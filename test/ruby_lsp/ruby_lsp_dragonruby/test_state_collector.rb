# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestStateCollector < Minitest::Test
      include RegistryTestHelper

      def setup
        @registry = load_registry(valid_files)
        @store = StateStore.new
        @resolver = Resolver.new(@registry, state_store: @store)
        @collector = StateCollector.new(@registry, @resolver)
      end

      def test_records_initialization_and_assignment_writes
        collect("def tick(args)\n  args.state.score ||= 0\n  args.state.score = 1\nend\n")

        entry = @store.entry("score")
        assert_equal 2, entry.write_count
        assert_equal [:initialization, :assignment], entry.writes.map(&:kind)
        assert_equal ["Integer"], entry.types
      end

      def test_records_write_ranges
        collect("def tick(args)\n  args.state.score ||= 0\nend\n")

        site = @store.entry("score").writes.first
        assert_equal "file:///test.rb", site.uri
        assert_equal 1, site.line
        assert_equal 13, site.character
      end

      def test_nested_paths_create_intermediate_nodes
        collect("def tick(args)\n  args.state.player.x ||= 0\nend\n")

        assert @store.path?("player")
        assert @store.path?("player.x")
        assert_equal ["x"], @store.child_names("player")
        assert_equal ["GTK::Entity"], @store.entry("player").types
        assert_equal ["Integer"], @store.entry("player.x").types
      end

      def test_hash_literal_keys_become_child_paths
        collect("def tick(args)\n  args.state.player = {x: 0, name: \"a\"}\nend\n")

        assert_equal ["name", "x"], @store.child_names("player")
        assert_equal ["Integer"], @store.entry("player.x").types
        assert_equal ["String"], @store.entry("player.name").types
      end

      def test_nested_hash_literals_recurse
        collect("def tick(args)\n  args.state.player = {sprite: {path: \"a.png\"}}\nend\n")

        assert_equal ["path"], @store.child_names("player.sprite")
      end

      def test_string_hash_keys_become_child_paths
        collect("def tick(args)\n  args.state.player = {\"x\" => 0}\nend\n")

        assert_equal ["x"], @store.child_names("player")
      end

      def test_alias_of_state_records_writes
        collect("def tick(args)\n  s = args.state\n  s.score ||= 0\nend\n")

        assert @store.path?("score")
      end

      def test_alias_of_state_sub_path_extend_the_path
        collect("def tick(args)\n  p = args.state.player\n  p.x ||= 0\nend\n")

        assert @store.path?("player.x")
      end

      def test_new_entity_rhs_infers_the_entity_type
        collect("def tick(args)\n  args.state.player = args.state.new_entity(:player)\nend\n")

        assert_equal ["GTK::Entity"], @store.entry("player").types
      end

      def test_registry_expression_rhs_infers_its_type
        collect("def tick(args)\n  args.state.kb = args.inputs.keyboard\nend\n")

        assert_equal ["GTK::Keyboard"], @store.entry("kb").types
      end

      def test_core_expression_rhs_infers_its_type
        collect("def tick(args)\n  args.state.down = args.inputs.base\nend\n")

        assert_equal ["Boolean"], @store.entry("down").types
      end

      def test_literal_rhs_types
        collect(<<~RUBY)
          def tick(args)
            args.state.a ||= 1.5
            args.state.b ||= "text"
            args.state.c ||= :sym
            args.state.d ||= true
            args.state.e ||= [1]
          end
        RUBY

        assert_equal ["Float"], @store.entry("a").types
        assert_equal ["String"], @store.entry("b").types
        assert_equal ["Symbol"], @store.entry("c").types
        assert_equal ["Boolean"], @store.entry("d").types
        assert_equal ["Array"], @store.entry("e").types
      end

      def test_unresolvable_rhs_is_unknown
        collect("def tick(args)\n  args.state.score ||= mystery\nend\n")

        assert_equal ["Unknown"], @store.entry("score").types
      end

      def test_reads_are_not_recorded
        collect(<<~RUBY)
          def tick(args)
            args.state.score
            puts args.state.player.x
          end
        RUBY

        refute @store.path?("score")
        refute @store.path?("player")
        assert @store.empty?
      end

      def test_writes_inside_attr_gtk_classes_are_recorded
        source = <<~RUBY
          class Game
            attr_gtk

            def tick
              state.score ||= 0
            end
          end
        RUBY

        collect_with_index(source)

        assert @store.path?("score")
      end

      def test_bracket_writes_are_not_recorded
        collect(<<~RUBY)
          def tick(args)
            args.state[:score] ||= 0
            args.state["lives"] = 3
          end
        RUBY

        assert @store.empty?
      end

      def test_incomplete_writes_do_not_raise
        [
          "def tick(args)\n  args.state.\nend\n",
          "def tick(args)\n  args.state.sc\nend\n",
          "def tick(args)\n  args.state.player = {\nend\n",
          "def tick(args)\n  args.state.score ||=\nend\n"
        ].each do |source|
          collect(source)
        end
      end

      private

      def collect(source)
        uri = URI("file:///test.rb")
        records = @collector.collect(Prism.parse(source).value, uri)
        @store.replace(uri, records)
        records
      end

      def collect_with_index(source)
        index = RubyIndexer::Index.new
        IndexingEnhancement.registry = @registry
        index.index_single(URI("file:///test.rb"), source)
        resolver = Resolver.new(@registry, index: index, state_store: @store)
        collector = StateCollector.new(@registry, resolver)
        uri = URI("file:///test.rb")
        @store.replace(uri, collector.collect(Prism.parse(source).value, uri))
      ensure
        IndexingEnhancement.registry = nil
      end
    end
  end
end
