# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestStateTracker < Minitest::Test
      include RegistryTestHelper
      include NodeContextHelper

      def setup
        @registry = load_registry(valid_files)
        @logger = quiet_logger
      end

      def test_workspace_scan_indexes_ruby_files
        files = {
          "app/main.rb" => "def tick(args)\n  args.state.score ||= 0\nend\n",
          "app/player.rb" => "def tick(args)\n  args.state.player.x ||= 0\nend\n",
          "vendor/gem.rb" => "def tick(args)\n  args.state.vendored ||= 0\nend\n",
          "node_modules/pkg.rb" => "def tick(args)\n  args.state.npm ||= 0\nend\n",
          "tmp/scratch.rb" => "def tick(args)\n  args.state.tmp ||= 0\nend\n"
        }

        with_data(files) do |dir|
          tracker = StateTracker.new(@registry, workspace_path: dir, logger: @logger)
          tracker.ensure_workspace_scanned

          assert tracker.path?("score")
          assert tracker.path?("player.x")
          refute tracker.path?("vendored")
          refute tracker.path?("npm")
          refute tracker.path?("tmp")
        end
      end

      def test_scan_runs_once
        with_data("app/main.rb" => "def tick(args)\n  args.state.score ||= 0\nend\n") do |dir|
          tracker = StateTracker.new(@registry, workspace_path: dir, logger: @logger)
          tracker.ensure_workspace_scanned
          File.delete(File.join(dir, "app/main.rb"))
          tracker.ensure_workspace_scanned

          assert tracker.path?("score")
        end
      end

      def test_scan_waits_until_initial_indexing_completes
        with_data("app/main.rb" => "def tick(args)\n  args.state.score ||= 0\nend\n") do |dir|
          index = RubyIndexer::Index.new
          tracker = StateTracker.new(@registry, index: index, workspace_path: dir, logger: @logger)

          tracker.ensure_workspace_scanned
          refute tracker.path?("score")

          index.instance_variable_set(:@initial_indexing_completed, true)
          tracker.ensure_workspace_scanned
          assert tracker.path?("score")
        end
      end

      def test_replace_source_replaces_only_that_file
        tracker = StateTracker.new(@registry, logger: @logger)
        tracker.replace_source(URI("file:///a.rb"), "def tick(args)\n  args.state.a ||= 0\nend\n")
        tracker.replace_source(URI("file:///b.rb"), "def tick(args)\n  args.state.b ||= 0\nend\n")
        tracker.replace_source(URI("file:///a.rb"), "def tick(args)\n  args.state.c ||= 0\nend\n")

        refute tracker.path?("a")
        assert tracker.path?("b")
        assert tracker.path?("c")
      end

      def test_remove_drops_the_files_contributions
        tracker = StateTracker.new(@registry, logger: @logger)
        tracker.replace_source(URI("file:///a.rb"), "def tick(args)\n  args.state.a ||= 0\nend\n")
        tracker.remove(URI("file:///a.rb"))

        refute tracker.path?("a")
        assert tracker.store.empty?
      end

      def test_entry_with_context_falls_back_to_the_current_ast
        tracker = StateTracker.new(@registry, logger: @logger)
        context = locate_context(<<~RUBY, adjust: 0)
          def tick(args)
            args.state.score ||= 0
            args.state.sco‸re
          end
        RUBY

        entry = tracker.entry_with_context("score", context)

        assert_equal 1, entry.write_count
        assert_equal ["Integer"], entry.types
        assert_nil entry.writes.first.uri
      end

      def test_entry_with_context_prefers_the_store
        tracker = StateTracker.new(@registry, logger: @logger)
        tracker.replace_source(URI("file:///a.rb"), "def tick(args)\n  args.state.score ||= 0\n  args.state.score = 1\nend\n")
        context = locate_context("def tick(args)\n  args.state.score ||= 0\n  args.state.sco‸re\nend", adjust: 0)

        entry = tracker.entry_with_context("score", context)

        assert_equal 2, entry.write_count
      end

      def test_broken_sources_do_not_raise
        tracker = StateTracker.new(@registry, logger: @logger)

        tracker.replace_source(URI("file:///a.rb"), "def tick(args)\n  args.state.")
        tracker.replace_source(URI("file:///b.rb"), nil)
        tracker.remove(nil)

        assert tracker.store.empty?
      end
    end
  end
end
