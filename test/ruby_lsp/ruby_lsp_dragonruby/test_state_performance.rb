# frozen_string_literal: true

require "test_helper"
require_relative "../../../benchmark/sample_workspace"

module RubyLsp
  module Dragonruby
    class TestStatePerformance < Minitest::Test
      include RegistryTestHelper

      def test_workspace_scan_meets_the_budget
        Benchmarks::SampleWorkspace.with_workspace do |dir|
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
    end
  end
end
