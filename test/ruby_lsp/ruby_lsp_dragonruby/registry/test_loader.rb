# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestRegistryLoader < Minitest::Test
      include RegistryTestHelper

      def setup
        @registry = load_registry(valid_files)
      end

      def test_builds_all_types
        expected = [
          "GTK::Args",
          "GTK::Base",
          "GTK::Entity",
          "GTK::Inputs",
          "GTK::Keyboard",
          "GTK::Keys",
          "GTK::State"
        ]
        assert_equal expected, @registry.type_names.sort
      end

      def test_metadata
        metadata = @registry.metadata
        assert_equal "5.0", metadata.dragonruby_version
        assert_equal "2026-09-25", metadata.curated_at
        assert_equal 1, metadata.schema_version
      end

      def test_members_and_kinds
        args = @registry.type("GTK::Args")
        assert_equal %w[inputs state score mystery], args.members.map(&:name)
        assert_predicate args.member("inputs"), :attribute?
        assert_predicate args.member("score"), :method?
      end

      def test_union_and_unknown_returns
        args = @registry.type("GTK::Args")
        assert_predicate args.member("score").returns, :union?
        assert_equal %w[Integer Float], args.member("score").returns.names
        assert_predicate args.member("mystery").returns, :unknown?
      end

      def test_parent_members_are_inherited
        inputs = @registry.type("GTK::Inputs")
        assert_equal "GTK::Base", inputs.parent_name
        assert_predicate inputs.member("base"), :attribute?
        assert_nil @registry.type("GTK::Base").member("inputs")
      end

      def test_core_backing_is_inherited
        types = <<~YAML
          types:
            - name: GTK::Collection
              core_backing: Array
              members: []
            - name: GTK::Sprites
              parent: GTK::Collection
              members: []
        YAML
        registry = load_registry({"metadata.yml" => METADATA, "types.yml" => types})

        assert_equal "Array", registry.type("GTK::Collection").core_backing
        assert_equal "Array", registry.type("GTK::Sprites").core_backing
      end

      def test_generated_members
        keyboard = @registry.type("GTK::Keyboard")
        assert_equal ["a", "b", "key_down"], keyboard.members.map(&:name).sort
        assert_equal ["bee"], keyboard.member("b").aliases
        assert_equal "The a key", keyboard.member("a").doc
        assert_equal ["GTK::Keys"], keyboard.member("key_down").returns.names
      end

      def test_params
        params = @registry.type("GTK::Keys").member("key_down?").params
        assert_equal %i[required keyword block], params.map(&:kind)
        assert_equal "key", params[0].name
        assert_equal ["Symbol"], params[0].type.names
        assert_nil params[2].name
        assert_predicate params[2], :block?
      end

      def test_primitive_schemas
        schema = @registry.schema("sprite")
        assert_equal "sprite", schema.primitive_marker
        key = schema.key("w")
        assert_predicate key, :default?
        assert_equal 0, key.default
        assert_equal [0, 1], key.allowed_values
        assert_equal ["Numeric"], key.type.names
      end

      def test_registry_is_immutable
        assert_predicate @registry, :frozen?
        assert_predicate @registry.types, :frozen?
        assert_predicate @registry.type("GTK::Args"), :frozen?
        assert_predicate @registry.type("GTK::Args").members, :frozen?
      end

      def test_lenient_load_does_not_raise_without_metadata
        registry = load_registry({"types.yml" => TYPES})
        assert_nil registry.metadata
        assert_equal 7, registry.types.size
      end

      def test_lenient_load_survives_unparseable_yaml
        logger = quiet_logger
        files = {"metadata.yml" => METADATA, "types.yml" => TYPES, "broken.yml" => "types: ["}
        registry = load_registry(files, logger: logger)
        assert_equal 7, registry.types.size
        assert logger.messages.any? { |message| message.include?("could not parse YAML") }
      end

      def test_duplicate_metadata_document_is_reported
        logger = quiet_logger
        files = {
          "metadata.yml" => METADATA,
          "metadata2.yml" => METADATA,
          "types.yml" => TYPES
        }
        registry = load_registry(files, logger: logger)

        assert_equal 7, registry.types.size
        assert logger.messages.any? { |message| message.include?("duplicate registry metadata document") }
      end

      def test_validator_skips_bad_members_but_keeps_type
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              members:
                - {name: good, kind: attribute, returns: Boolean, doc: Good}
                - {name: bad, kind: attribute, returns: GTK::Nope, doc: Bad}
        YAML
        registry = load_registry({"metadata.yml" => METADATA, "types.yml" => type_yaml})
        assert_equal ["good"], registry.type("GTK::Thing").members.map(&:name)
      end
    end
  end
end
