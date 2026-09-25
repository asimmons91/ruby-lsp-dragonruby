# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestCoverage < Minitest::Test
      include RegistryTestHelper

      COVERAGE = <<~YAML
        areas:
          - id: args
            title: args
            docs: "https://docs.dragonruby.org/#/api/"
            types: [GTK::Args]
          - id: args.inputs
            title: Inputs
            docs: "https://docs.dragonruby.org/#/api/inputs"
            types: [GTK::Inputs, GTK::Keyboard]
          - id: broken
            title: Broken
            docs: "https://example.com"
            types: [GTK::Missing]
      YAML

      COVERAGE_OK = <<~YAML
        areas:
          - id: args
            title: args
            docs: "https://docs.dragonruby.org/#/api/"
            types: [GTK::Args]
          - id: args.inputs
            title: Inputs
            docs: "https://docs.dragonruby.org/#/api/inputs"
            types: [GTK::Inputs, GTK::Keyboard]
      YAML

      def test_reports_covered_and_missing_areas
        files = valid_files.merge("coverage.yml" => COVERAGE)
        with_registry(files) do |registry, dir|
          coverage = Registry::Coverage.call(registry, data_dir: dir)
          refute coverage.covered?
          assert_equal %w[args args.inputs broken], coverage.areas.map(&:id)
          assert coverage.areas[0].covered?
          assert coverage.areas[1].covered?
          refute coverage.areas[2].covered?
          assert_equal ["GTK::Missing"], coverage.areas[2].missing_types
          assert_equal 4, coverage.areas[1].member_count
          assert_equal [coverage.areas[2]], coverage.incomplete
        end
      end

      def test_report_lists_types_and_metadata
        files = valid_files.merge("coverage.yml" => COVERAGE)
        with_registry(files) do |registry, dir|
          report = Registry::Coverage.call(registry, data_dir: dir).to_s
          assert_includes report, "targets DragonRuby 5.0"
          assert_includes report, "GTK::Args"
          assert_includes report, "GTK::Keyboard"
        end
      end

      def test_all_covered
        files = valid_files.merge("coverage.yml" => COVERAGE_OK)
        with_registry(files) do |registry, dir|
          assert Registry::Coverage.call(registry, data_dir: dir).covered?
        end
      end
    end
  end
end
