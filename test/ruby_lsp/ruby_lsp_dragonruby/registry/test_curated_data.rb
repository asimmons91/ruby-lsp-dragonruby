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

      def test_primitive_schemas_are_curated
        %w[sprite label solid border line].each do |name|
          schema = registry.schema(name)
          refute_nil schema, "missing schema #{name}"
          assert_equal name, schema.primitive_marker
          refute_empty schema.keys, "schema #{name} has no keys"
        end

        screenshot = registry.schema("screenshot")
        refute_nil screenshot
        assert_includes screenshot.keys.map(&:name), "path"
      end

      def test_output_collections_link_primitive_schemas
        {
          "GTK::Outputs::Sprites" => ["sprite"],
          "GTK::Outputs::Labels" => ["label"],
          "GTK::Outputs::Solids" => ["solid"],
          "GTK::Outputs::Borders" => ["border"],
          "GTK::Outputs::Lines" => ["line"],
          "GTK::Outputs::Screenshots" => ["screenshot"]
        }.each do |type_name, schema_names|
          assert_equal schema_names, registry.type(type_name).accepts_primitive, type_name
        end

        assert_equal %w[sprite label solid border line],
          registry.type("GTK::Outputs::Primitives").accepts_primitive
      end

      def test_macros_are_curated
        macro = registry.macro("attr_gtk")
        refute_nil macro
        assert_equal ["attr_dr"], macro.aliases

        %w[args state inputs outputs grid geometry gtk layout audio easing events runtime passes].each do |name|
          assert macro.accessor?(name), "attr_gtk is missing accessor #{name}"
        end

        sprite = registry.macro("attr_sprite")
        refute_nil sprite
        assert_equal "sprite", sprite.primitive
        assert_equal registry.schema("sprite").keys.map(&:name), sprite.accessors.map(&:name)
      end

      def test_core_extension_types_are_curated
        %w[Numeric Integer Float Array Hash Kernel].each do |name|
          type = registry.type(name)
          refute_nil type, "missing core extension type #{name}"
          assert_predicate type, :core_extension?
          assert_predicate type, :open?
          refute_empty type.all_members, "#{name} has no members"
        end
      end

      def test_numeric_extensions_are_curated
        %w[frame frame_index elapsed_time elapsed? to_sf to_si lerp remap clamp_wrap mid min max seconds
          to_degrees to_radians].each do |name|
          assert registry.type("Numeric").member?(name), "Numeric is missing #{name}"
        end

        numeric = registry.type("Numeric")
        assert numeric.member("frame_index").offered_for?(:class)
        assert numeric.member("seconds").offered_for?(:instance)
        refute numeric.member("seconds").offered_for?(:class)
      end

      def test_hash_and_array_geometry_mixins_are_curated
        expected = %w[intersect_rect? inside_rect? scale_rect angle_to angle_from point_inside_circle?
          center_inside_rect anchor_rect rect_center_point]

        expected.each do |name|
          assert registry.type("Hash").member?(name), "Hash is missing #{name}"
          assert registry.type("Array").member?(name), "Array is missing #{name}"
        end
      end

      def test_array_instance_extensions_are_curated
        %w[map_2d include_any? any_intersect_rect? reject_nil reject_false].each do |name|
          assert registry.type("Array").member?(name), "Array is missing #{name}"
        end

        assert registry.type("Array").member("map").offered_for?(:class)
        refute registry.type("Array").member("map_2d").offered_for?(:class)
      end

      def test_kernel_extensions_are_curated
        %w[tick_count global_tick_count].each do |name|
          assert registry.type("Kernel").member?(name), "Kernel is missing #{name}"
        end
      end

      def test_core_extension_coverage_area_is_covered
        coverage = Registry::Coverage.call(registry, data_dir: DATA_DIR)
        area = coverage.areas.find { |candidate| candidate.id == "core-extensions" }

        refute_nil area
        assert_predicate area, :covered?
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
