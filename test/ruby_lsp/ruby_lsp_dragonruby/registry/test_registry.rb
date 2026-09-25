# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestRegistry < Minitest::Test
      include RegistryTestHelper

      def test_type_and_schema_lookup
        registry = load_registry(valid_files)
        assert_instance_of Registry::Type, registry.type("GTK::Args")
        assert_instance_of Registry::PrimitiveSchema, registry.schema("sprite")
        assert_nil registry.type("GTK::Nope")
        assert_nil registry.schema("nope")
      end

      def test_known_type
        registry = load_registry(valid_files)
        assert registry.known_type?("Unknown")
        assert registry.known_type?("Integer")
        assert registry.known_type?("GTK::Args")
        refute registry.known_type?("GTK::Nope")
      end

      def test_member_lookup_and_predicates
        registry = load_registry(valid_files)
        inputs = registry.type("GTK::Inputs")
        assert inputs.member?("base")
        refute inputs.member?("nope")
        assert inputs.own_member("keyboard")
        assert_nil inputs.own_member("base")
      end

      def test_reset_clears_memoized_registry
        Registry.instance_variable_set(:@default, :sentinel)
        Registry.reset!
        assert_nil Registry.default
      ensure
        Registry.reset!
      end

      def test_validate_raises_on_errors
        with_data({"metadata.yml" => METADATA, "types.yml" => "types:\n  - members: []\n"}) do |dir|
          error = assert_raises(Registry::InvalidDataError) { Registry.validate!(data_dir: dir, logger: quiet_logger) }
          assert_includes error.message, "missing required field `name`"
        end
      end

      def test_validate_logs_issues_to_logger
        io = StringIO.new
        logger = Logger.new(io)
        with_data({"metadata.yml" => METADATA, "types.yml" => "types:\n  - members: []\n"}) do |dir|
          assert_raises(Registry::InvalidDataError) { Registry.validate!(data_dir: dir, logger: logger) }
        end

        assert_includes io.string, "missing required field `name`"
      end

      def test_validate_returns_warnings
        type_yaml = <<~YAML
          types:
            - name: GTK::Keyboard
              members:
                - {name: up, kind: attribute, returns: Boolean, doc: Directional}
                - {name: up_arrow, kind: attribute, returns: Boolean, doc: Arrow, aliases: [up]}
        YAML
        with_data({"metadata.yml" => METADATA, "types.yml" => type_yaml}) do |dir|
          issues = Registry.validate!(data_dir: dir, logger: quiet_logger)
          assert_equal 1, issues.count(&:warning?)
        end
      end
    end
  end
end
