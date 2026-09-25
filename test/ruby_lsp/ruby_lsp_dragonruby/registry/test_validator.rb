# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestRegistryValidator < Minitest::Test
      include RegistryTestHelper

      def test_valid_fixture_has_no_errors
        issues = validation_issues(valid_files)
        assert_empty error_messages(issues)
      end

      def test_missing_metadata
        issues = issues_for(nil, metadata: nil)
        assert_includes error_messages(issues), "missing registry metadata (dragonruby_version and curated_at)"
      end

      def test_metadata_requires_iso_date
        issues = issues_for("types: []", metadata: "dragonruby_version: \"5.0\"\ncurated_at: someday\n")
        assert_includes error_messages(issues), "`curated_at` must be an ISO 8601 date"
      end

      def test_duplicate_type_names_keep_first
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              members:
                - {name: one, kind: attribute, returns: Boolean, doc: One}
            - name: GTK::Thing
              members:
                - {name: two, kind: attribute, returns: Boolean, doc: Two}
        YAML
        registry = load_registry({"metadata.yml" => METADATA, "types.yml" => type_yaml})
        assert_equal ["one"], registry.type("GTK::Thing").members.map(&:name)
        assert_includes error_messages(issues_for(type_yaml)), "duplicate type name `GTK::Thing`"
      end

      def test_missing_type_name
        issues = issues_for("types:\n  - members: []\n")
        assert_includes error_messages(issues), "missing required field `name`"
      end

      def test_duplicate_member_names_drop_second
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              members:
                - {name: dup, kind: attribute, returns: Boolean, doc: One}
                - {name: dup, kind: attribute, returns: Boolean, doc: Two}
        YAML
        registry = load_registry({"metadata.yml" => METADATA, "types.yml" => type_yaml})
        assert_equal ["One"], registry.type("GTK::Thing").members.map(&:doc)
        assert_includes error_messages(issues_for(type_yaml)), "duplicate member name `dup`"
      end

      def test_invalid_kind_drops_member
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              members:
                - {name: bad, kind: property, returns: Boolean, doc: Bad}
        YAML
        assert_includes error_messages(issues_for(type_yaml)), "invalid kind `property`"
      end

      def test_attribute_with_params_drops_member
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              members:
                - name: bad
                  kind: attribute
                  returns: Boolean
                  doc: Bad
                  params: [{name: x, kind: required, type: Integer}]
        YAML
        assert_includes error_messages(issues_for(type_yaml)), "attribute cannot declare params"
      end

      def test_missing_doc_drops_member
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              members:
                - {name: bad, kind: attribute, returns: Boolean}
        YAML
        assert_includes error_messages(issues_for(type_yaml)), "missing required field `doc`"
      end

      def test_unresolved_return_drops_member
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              members:
                - {name: bad, kind: attribute, returns: GTK::Nope, doc: Bad}
        YAML
        assert_includes error_messages(issues_for(type_yaml)), "unresolved type `GTK::Nope`"
      end

      def test_unresolved_param_type_drops_member
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              members:
                - name: bad
                  kind: method
                  returns: Boolean
                  doc: Bad
                  params: [{name: x, kind: required, type: GTK::Nope}]
        YAML
        assert_includes error_messages(issues_for(type_yaml)), "unresolved type `GTK::Nope`"
      end

      def test_invalid_param_kind_drops_member
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              members:
                - name: bad
                  kind: method
                  returns: Boolean
                  doc: Bad
                  params: [{name: x, kind: splat, type: Integer}]
        YAML
        assert_includes error_messages(issues_for(type_yaml)), "invalid param kind `splat`"
      end

      def test_named_param_requires_name
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              members:
                - name: bad
                  kind: method
                  returns: Boolean
                  doc: Bad
                  params: [{kind: required, type: Integer}]
        YAML
        assert_includes error_messages(issues_for(type_yaml)), "param `required` is missing a `name`"
      end

      def test_unknown_parent_is_cleared
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              parent: GTK::Nope
              members:
                - {name: ok, kind: attribute, returns: Boolean, doc: Ok}
        YAML
        registry = load_registry({"metadata.yml" => METADATA, "types.yml" => type_yaml})
        assert_nil registry.type("GTK::Thing").parent_name
        assert_includes error_messages(issues_for(type_yaml)), "unresolved parent type `GTK::Nope`"
      end

      def test_cyclic_parents_are_cleared
        type_yaml = <<~YAML
          types:
            - name: GTK::A
              parent: GTK::B
              members: []
            - name: GTK::B
              parent: GTK::A
              members: []
        YAML
        registry = load_registry({"metadata.yml" => METADATA, "types.yml" => type_yaml})
        assert_nil registry.type("GTK::A").parent_name
        assert_includes error_messages(issues_for(type_yaml)), "cyclic parent chain detected"
      end

      def test_dangling_accepts_primitive_is_cleared
        type_yaml = <<~YAML
          types:
            - name: GTK::Sprites
              accepts_primitive: nope
              members:
                - {name: push, kind: method, returns: GTK::Sprites, doc: Push}
        YAML
        registry = load_registry({"metadata.yml" => METADATA, "types.yml" => type_yaml})
        assert_nil registry.type("GTK::Sprites").accepts_primitive
        assert_includes error_messages(issues_for(type_yaml)), "dangling accepts_primitive reference `nope`"
      end

      def test_accepts_primitive_resolves
        type_yaml = <<~YAML
          types:
            - name: GTK::Sprites
              accepts_primitive: sprite
              members:
                - {name: push, kind: method, returns: GTK::Sprites, doc: Push}
        YAML
        registry = load_registry({"metadata.yml" => METADATA, "types.yml" => type_yaml, "schemas.yml" => SCHEMAS})
        assert_equal "sprite", registry.type("GTK::Sprites").accepts_primitive
      end

      def test_dangling_name_list_reference
        type_yaml = <<~YAML
          types:
            - name: GTK::Keyboard
              generates:
                - names: nope
                  members:
                    - {name: "{{name}}", kind: attribute, returns: Boolean, doc: Key}
        YAML
        registry = load_registry({"metadata.yml" => METADATA, "types.yml" => type_yaml})
        assert_empty registry.type("GTK::Keyboard").members
        assert_includes error_messages(issues_for(type_yaml)), "dangling name list reference `nope`"
      end

      def test_duplicate_schema_names_keep_first
        schemas = <<~YAML
          schemas:
            - {name: sprite, primitive_marker: sprite, keys: []}
            - {name: sprite, primitive_marker: label, keys: []}
        YAML
        registry = load_registry({"metadata.yml" => METADATA, "schemas.yml" => schemas})
        assert_equal "sprite", registry.schema("sprite").primitive_marker
        assert_includes error_messages(issues_for("types: []", schemas: schemas)), "duplicate schema name `sprite`"
      end

      def test_duplicate_primitive_keys_drop_second
        schemas = <<~YAML
          schemas:
            - name: sprite
              keys:
                - {name: w, type: Numeric, doc: Width}
                - {name: w, type: Numeric, doc: Other}
        YAML
        registry = load_registry({"metadata.yml" => METADATA, "schemas.yml" => schemas})
        assert_equal 1, registry.schema("sprite").keys.size
        assert_includes error_messages(issues_for("types: []", schemas: schemas)), "duplicate primitive key `w`"
      end

      def test_primitive_key_type_must_resolve
        schemas = <<~YAML
          schemas:
            - name: sprite
              keys:
                - {name: w, type: GTK::Nope, doc: Width}
        YAML
        issues = issues_for("types: []", schemas: schemas)
        assert_includes error_messages(issues), "unresolved type `GTK::Nope`"
      end

      def test_alias_collision_warns_and_drops_alias
        type_yaml = <<~YAML
          types:
            - name: GTK::Keyboard
              members:
                - {name: up, kind: attribute, returns: Boolean, doc: Directional}
                - {name: up_arrow, kind: attribute, returns: Boolean, doc: Arrow, aliases: [up, arrow]}
        YAML
        issues = issues_for(type_yaml)
        assert_empty error_messages(issues)
        warnings = issues.select(&:warning?).map(&:message)
        assert_includes warnings, "alias `up` is already a member or alias"
        registry = load_registry({"metadata.yml" => METADATA, "types.yml" => type_yaml})
        assert_equal ["arrow"], registry.type("GTK::Keyboard").member("up_arrow").aliases
      end

      def test_invalid_boolean_flag
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              open: 1
              members:
                - {name: ok, kind: attribute, returns: Boolean, doc: Ok}
        YAML
        issues = issues_for(type_yaml)
        assert_includes error_messages(issues), "`open` must be true or false"
      end

      def test_name_list_entries_require_names
        names = <<~YAML
          names:
            keys:
              - {aliases: [a]}
        YAML
        issues = issues_for("types: []", names: names)
        assert_includes error_messages(issues), "name list entry is missing a `name`"
      end

      def test_union_with_one_unresolved_name_drops_member
        type_yaml = <<~YAML
          types:
            - name: GTK::Thing
              members:
                - {name: bad, kind: attribute, returns: [Boolean, GTK::Nope], doc: Bad}
        YAML
        issues = issues_for(type_yaml)
        assert_includes error_messages(issues), "unresolved type `GTK::Nope`"
      end
    end
  end
end
