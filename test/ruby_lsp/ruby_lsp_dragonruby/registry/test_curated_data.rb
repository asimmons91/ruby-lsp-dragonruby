# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestCuratedData < Minitest::Test
      include RegistryTestHelper

      DATA_DIR = Registry::DATA_DIR

      def self.registry
        @registry ||= Registry::Loader.new(data_dir: DATA_DIR, logger: RubyLsp::Dragonruby::Logger.new(nil)).load
      end

      def registry
        self.class.registry
      end

      def test_metadata_records_target_version
        metadata = registry.metadata
        refute_nil metadata
        assert_match(/\A\d+\.\d+\z/, metadata.dragonruby_version)
        assert_match(/\A\d{4}-\d{2}-\d{2}\z/, metadata.curated_at)
        assert_equal 1, metadata.schema_version
      end

      def test_validator_passes_without_errors
        issues = Registry::Loader.new(data_dir: DATA_DIR, logger: quiet_logger).validation_issues
        assert_empty error_messages(issues)
      end

      def test_m1_areas_are_covered
        coverage = Registry::Coverage.call(registry, data_dir: DATA_DIR)
        assert coverage.covered?, "incomplete areas: #{coverage.incomplete.map(&:id).join(", ")}"
      end

      def test_args_tree_is_wired
        args = registry.type("GTK::Args")
        %w[inputs outputs state grid geometry easing audio gtk layout events].each do |member|
          assert args.member?(member), "GTK::Args is missing #{member}"
        end
      end

      def test_keyboard_keys_are_generated
        keyboard = registry.type("GTK::Keyboard")
        assert keyboard.member?("a")
        assert keyboard.member?("space")
        assert keyboard.member?("left_arrow")
        assert_equal ["up_wasd"], keyboard.member("w_scancode").aliases
        assert registry.type("GTK::KeyboardKeys").member?("space")
      end

      def test_output_collections_inherit_shared_members
        sprites = registry.type("GTK::Outputs::Sprites")
        assert_equal "GTK::Outputs::Collection", sprites.parent_name
        assert sprites.member?("<<")
        assert registry.type("GTK::Outputs::RenderTarget").member?("set")
      end

      def test_open_types
        assert_predicate registry.type("GTK::State"), :open?
        assert_predicate registry.type("GTK::Entity"), :open?
      end

      def test_primitive_schemas_are_placeholders
        %w[sprite label solid border line].each do |name|
          schema = registry.schema(name)
          refute_nil schema, "missing schema #{name}"
          assert_equal name, schema.primitive_marker
          assert_empty schema.keys
        end
      end

      def test_registry_loads_under_100ms
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Registry::Loader.new(data_dir: DATA_DIR, logger: quiet_logger).load
        elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000

        assert_operator elapsed_ms, :<, 100, "registry took #{elapsed_ms.round(1)}ms to load"
      end
    end
  end
end
