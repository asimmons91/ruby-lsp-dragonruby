# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestStateStore < Minitest::Test
      def setup
        @store = StateStore.new
      end

      def test_replace_indexes_paths_children_and_types
        @store.replace("file:///a.rb", [
          record("player", "", site(line: 0, type_name: "GTK::Entity")),
          record("player.x", "player", site(line: 1))
        ])

        assert @store.path?("player")
        assert @store.path?("player.x")
        assert_equal ["player"], @store.child_names("")
        assert_equal ["x"], @store.child_names("player")
        assert_equal ["Integer"], @store.entry("player.x").types
        assert_equal 1, @store.entry("player.x").write_count
      end

      def test_types_form_a_union_across_write_sites
        @store.replace("file:///a.rb", [record("score", "", site(line: 0, type_name: "Integer"))])
        @store.replace("file:///b.rb", [record("score", "", site(uri: "file:///b.rb", line: 0, type_name: "String"))])

        assert_equal ["Integer", "String"], @store.entry("score").types
      end

      def test_all_unknown_types_collapse_to_unknown
        @store.replace("file:///a.rb", [
          record("score", "", site(line: 0, type_name: "Unknown")),
          record("score", "", site(line: 1, kind: :assignment, type_name: "Unknown"))
        ])

        assert_equal ["Unknown"], @store.entry("score").types
      end

      def test_remove_drops_only_that_uris_contributions
        @store.replace("file:///a.rb", [
          record("score", "", site(line: 0)),
          record("player", "", site(line: 1, type_name: "GTK::Entity")),
          record("player.x", "player", site(line: 2))
        ])
        @store.replace("file:///b.rb", [record("score", "", site(uri: "file:///b.rb", line: 0, type_name: "String"))])

        @store.remove("file:///a.rb")

        assert @store.path?("score")
        assert_equal ["String"], @store.entry("score").types
        refute @store.path?("player")
        refute @store.path?("player.x")
        assert_equal ["score"], @store.child_names("")
      end

      def test_replace_replaces_the_previous_contributions_of_a_uri
        @store.replace("file:///a.rb", [record("score", "", site(line: 0))])
        @store.replace("file:///a.rb", [record("lives", "", site(line: 0))])

        refute @store.path?("score")
        assert @store.path?("lives")
      end

      def test_write_site_deduplication
        @store.replace("file:///a.rb", [
          record("score", "", site(line: 0)),
          record("score", "", site(line: 0))
        ])

        assert_equal 1, @store.entry("score").write_count
      end

      def test_initializations_sort_before_assignments_in_file_order
        @store.replace("file:///a.rb", [
          record("score", "", site(line: 5, kind: :assignment)),
          record("score", "", site(line: 3)),
          record("score", "", site(line: 1))
        ])
        @store.replace("file:///b.rb", [record("score", "", site(line: 0))])

        sorted = @store.entry("score").writes.sort_by(&:sort_key)

        assert_equal [[0, 0], [0, 1], [0, 3], [1, 5]], sorted.map { |site| [site.initialization? ? 0 : 1, site.line] }
      end

      def test_first_initialization_is_the_earliest_initialization_site
        @store.replace("file:///a.rb", [
          record("score", "", site(line: 4, kind: :assignment)),
          record("score", "", site(line: 2))
        ])

        assert_equal 2, @store.entry("score").first_initialization.line
      end

      def test_entry_and_children_for_unknown_paths_are_empty
        assert_nil @store.entry("nope")
        refute @store.path?("nope")
        assert_empty @store.child_names("nope")
      end

      private

      def site(line:, uri: "file:///a.rb", character: 0, kind: :initialization, type_name: "Integer")
        StateStore::WriteSite.new(
          uri: uri,
          line: line,
          character: character,
          end_line: line,
          end_character: character + 1,
          kind: kind,
          type_name: type_name
        )
      end

      def record(path, parent, site)
        StateStore::Record.new(path: path, parent: parent, site: site)
      end
    end
  end
end
