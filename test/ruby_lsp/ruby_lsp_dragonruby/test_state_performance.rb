# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestStatePerformance < Minitest::Test
      include RegistryTestHelper

      FILE_COUNT = 50
      LINES_PER_FILE = 200

      def test_workspace_scan_meets_the_budget
        with_sample_workspace do |dir|
          registry = load_registry(valid_files)
          tracker = StateTracker.new(registry, workspace_path: dir, logger: quiet_logger)

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          tracker.ensure_workspace_scanned
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

          assert tracker.path?("score")
          assert tracker.path?("file_0_key_0")
          assert_operator elapsed, :<, 1.0, "workspace scan took #{elapsed.round(3)}s"
        end
      end

      private

      def with_sample_workspace
        Dir.mktmpdir do |dir|
          FILE_COUNT.times do |index|
            path = File.join(dir, "app", "file_#{index}.rb")
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, sample_source(index))
          end

          yield dir
        end
      end

      def sample_source(index)
        body = "def tick_#{index}(args)\n"
        (LINES_PER_FILE - 3).times { |line| body << "  args.state.file_#{index}_key_#{line} ||= #{line}\n" }
        body << "  args.state.score ||= 0\n"
        body << "end\n"
        body
      end
    end
  end
end
