# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestIntegrationState < Minitest::Test
      include ServerTestHelper
      include RegistryTestHelper

      def test_completion_offers_writes_from_the_same_file
        source = "def tick(args)\n  args.state.score ||= 0\n  args.state.‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "score"
          assert_includes labels, "new_entity"
        end
      end

      def test_partial_state_key_filters_children
        source = "def tick(args)\n  args.state.score ||= 0\n  args.state.sc‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "score"
          refute_includes labels, "new_entity"
        end
      end

      def test_completion_after_a_state_sub_path
        source = <<~RUBY
          def tick(args)
            args.state.player = {x: 0, name: "player"}
            args.state.player.‸
          end
        RUBY

        with_cursor(source) do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "x"
          assert_includes labels, "name"
          assert_includes labels, "inside_rect?"
        end
      end

      def test_completion_through_a_nested_write
        source = <<~RUBY
          def tick(args)
            args.state.player.x ||= 0
            args.state.player.‸
          end
        RUBY

        with_cursor(source) do |server, uri, line, character|
          assert_includes completion_labels(server, uri, line, character), "x"
        end
      end

      def test_completion_through_a_state_alias
        source = "def tick(args)\n  s = args.state\n  s.score ||= 0\n  s.‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          assert_includes completion_labels(server, uri, line, character), "score"
        end
      end

      def test_completion_through_an_attr_gtk_state
        source = <<~RUBY
          class Game
            attr_gtk

            def tick
              state.score ||= 0
              state.‸
            end
          end
        RUBY

        with_cursor(source) do |server, uri, line, character|
          reindex(server, uri, source)
          labels = completion_labels(server, uri, line, character, trigger_character: ".")

          assert_includes labels, "score"
        end
      end

      def test_completion_offers_keys_written_in_another_file
        with_data("app/player.rb" => "def tick(args)\n  args.state.player.x ||= 0\nend\n") do |dir|
          with_cursor("def tick(args)\n  args.state.‸\nend\n") do |server, uri, line, character|
            state_tracker(server).workspace_path = dir
            mark_indexing_complete(server)

            assert_includes completion_labels(server, uri, line, character), "player"
          end
        end
      end

      def test_changed_file_replaces_its_keys
        with_data("app/player.rb" => "def tick(args)\n  args.state.old ||= 0\nend\n") do |dir|
          with_cursor("def tick(args)\n  args.state.‸\nend\n") do |server, uri, line, character|
            state_tracker(server).workspace_path = dir
            mark_indexing_complete(server)

            assert_includes completion_labels(server, uri, line, character), "old"

            path = File.join(dir, "app/player.rb")
            File.write(path, "def tick(args)\n  args.state.new_key ||= 0\nend\n")
            server.process_message(
              method: "workspace/didChangeWatchedFiles",
              params: {changes: [{uri: URI::Generic.from_path(path: path).to_s, type: 2}]}
            )

            labels = completion_labels(server, uri, line, character)
            assert_includes labels, "new_key"
            refute_includes labels, "old"
          end
        end
      end

      def test_deleted_file_removes_its_keys
        with_data("app/player.rb" => "def tick(args)\n  args.state.score ||= 0\nend\n") do |dir|
          with_cursor("def tick(args)\n  args.state.‸\nend\n") do |server, uri, line, character|
            state_tracker(server).workspace_path = dir
            mark_indexing_complete(server)

            assert_includes completion_labels(server, uri, line, character), "score"

            path = File.join(dir, "app/player.rb")
            File.delete(path)
            server.process_message(
              method: "workspace/didChangeWatchedFiles",
              params: {changes: [{uri: URI::Generic.from_path(path: path).to_s, type: 3}]}
            )

            refute_includes completion_labels(server, uri, line, character), "score"
          end
        end
      end

      def test_hover_shows_types_write_count_and_initialization
        source = <<~RUBY
          def tick(args)
            args.state.player.x ||= 0
            args.state.player.‸x
          end
        RUBY

        with_cursor(source) do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content, "player.x → Integer"
          assert_includes content, "1 write site"
          assert_includes content, "First initialized at"
        end
      end

      def test_hover_shows_a_union_when_writes_disagree
        source = <<~RUBY
          def tick(args)
            args.state.score ||= 0
            args.state.score = "high"
            args.state.sco‸re
          end
        RUBY

        with_cursor(source) do |server, uri, line, character|
          assert_includes hover_content(server, uri, line, character), "Integer | String"
        end
      end

      def test_hover_of_an_entity_member_through_a_state_path
        source = "def tick(args)\n  args.state.player.inside_re‸ct?(args.state.player.x)\nend\n"

        with_cursor(source) do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content, "inside_rect?(rect) → Boolean"
          assert_includes content, "inside the given rect"
        end
      end

      def test_hover_of_a_nested_path_with_a_colliding_middle_segment
        source = <<~RUBY
          def tick(args)
            args.state.player.x.y ||= 0
            args.state.player.x.‸y
          end
        RUBY

        with_cursor(source) do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content, "player.x.y → Integer"
          assert_includes content, "1 write site"
        end
      end

      def test_hover_across_files
        with_data("app/player.rb" => "def tick(args)\n  args.state.player.x ||= 0\nend\n") do |dir|
          source = "def tick(args)\n  args.state.player.‸x\nend\n"
          with_cursor(source) do |server, uri, line, character|
            state_tracker(server).workspace_path = dir
            mark_indexing_complete(server)

            content = hover_content(server, uri, line, character)

            assert_includes content, "player.x → Integer"
            assert_includes content, "app/player.rb"
          end
        end
      end

      def test_definition_returns_every_write_site
        source = <<~RUBY
          def tick(args)
            args.state.player.x = 1
            args.state.player.x ||= 0
            args.state.player.‸x
          end
        RUBY

        with_cursor(source) do |server, uri, line, character|
          locations = definition_locations(server, uri, line, character)

          assert_equal 2, locations.size
          assert_equal [2, 1], locations.map { |location| location.range.start.line }
          assert locations.all? { |location| location.uri == uri.to_s }
        end
      end

      def test_definition_across_files
        with_data("app/player.rb" => "def tick(args)\n  args.state.player.x ||= 0\nend\n") do |dir|
          source = "def tick(args)\n  args.state.player.‸x\nend\n"
          with_cursor(source) do |server, uri, line, character|
            state_tracker(server).workspace_path = dir
            mark_indexing_complete(server)

            locations = definition_locations(server, uri, line, character)

            assert_equal 1, locations.size
            assert_equal URI::Generic.from_path(path: File.join(dir, "app/player.rb")).to_s, locations.first.uri
            assert_equal 1, locations.first.range.start.line
          end
        end
      end

      def test_unknown_state_path_has_no_definition
        source = "def tick(args)\n  args.state.nope.‸x\nend\n"
        with_cursor(source) do |server, uri, line, character|
          assert_empty definition_locations(server, uri, line, character)
        end
      end

      def test_incomplete_write_does_not_break_completion
        source = "def tick(args)\n  args.state.player = {\n  args.state.‸\nend\n"
        with_cursor(source) do |server, uri, line, character|
          labels = completion_labels(server, uri, line, character)

          assert_includes labels, "new_entity"
        end
      end
    end
  end
end
