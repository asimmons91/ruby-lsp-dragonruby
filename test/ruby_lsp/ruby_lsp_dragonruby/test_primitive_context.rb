# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestPrimitiveContext < Minitest::Test
      include RegistryTestHelper

      def test_append_predicate
        assert PrimitiveContext.append?(call("items << { x: 0 }"))
        assert PrimitiveContext.append?(call("items.push({ x: 0 })"))
        assert PrimitiveContext.append?(call("items.concat([{ x: 0 }])"))
        refute PrimitiveContext.append?(call("items.changed?"))
        refute PrimitiveContext.append?(call("<< { x: 0 }"))
      end

      def test_hashes_finds_direct_and_array_hashes
        node = call("items << { x: 0 }")
        assert_equal 1, PrimitiveContext.hashes(node).size

        node = call("items << [1, { x: 0 }, { y: 1 }]")
        assert_equal 2, PrimitiveContext.hashes(node).size

        node = call("items << 5")
        assert_empty PrimitiveContext.hashes(node)
      end

      def test_unclosed_and_trailing_comma
        assert PrimitiveContext.unclosed?(hash("items << { x: 0,"))
        refute PrimitiveContext.unclosed?(hash("items << { x: 0 }"))

        assert PrimitiveContext.trailing_comma?(hash("items << { x: 0,"))
        refute PrimitiveContext.trailing_comma?(hash("items << { x: 0"))
      end

      def test_position_for_key_and_value
        assert_equal [:key, nil, nil], PrimitiveContext.position(hash("items << {"))
        assert_equal [:key, nil, nil], PrimitiveContext.position(hash("items << { x: 0,"))
        assert_equal [:key, nil, nil], PrimitiveContext.position(hash("items << { x: 0, knuckle"))

        kind, name, value = PrimitiveContext.position(hash("items << { x: 0, blend: :a"))
        assert_equal :value, kind
        assert_equal "blend", name
        assert_instance_of Prism::SymbolNode, value

        assert_equal [:key, nil, nil], PrimitiveContext.position(hash("items << { end"))
        assert_equal [:key, nil, nil], PrimitiveContext.position(hash("items << { end\n"))
      end

      def test_existing_keys_reads_symbol_and_string_keys
        keys = PrimitiveContext.existing_keys(hash('items << { x: 0, "y" => 1, z: 2 }'))
        assert_equal Set["x", "y", "z"], keys
      end

      def test_marker_value_and_restriction
        registry = registry_with_schemas
        schemas = [registry.schema("sprite"), registry.schema("solid")]

        assert_equal "solid", PrimitiveContext.marker_value(hash("items << { primitive_marker: :solid }"))
        assert_nil PrimitiveContext.marker_value(hash("items << { x: 0 }"))
        assert_equal ["solid"], PrimitiveContext.restricted_schemas(schemas, hash("items << { primitive_marker: :solid }")).map(&:name)
        assert_equal %w[sprite solid], PrimitiveContext.restricted_schemas(schemas, hash("items << { x: 0 }")).map(&:name)
      end

      def test_keys_by_name_and_allowed_values
        registry = registry_with_schemas
        keys = PrimitiveContext.keys_by_name(registry.schemas.values)

        assert_equal %w[sprite solid], keys["w"].map { |_key, schema| schema.name }
        assert_equal [0, 1], PrimitiveContext.allowed_values(keys, "w")
        assert_empty PrimitiveContext.allowed_values(keys, "nope")
      end

      def test_assoc_for_value
        node = hash("items << { x: 0, blend: :a")
        value = node.elements.last.value

        assert_equal node.elements.last, PrimitiveContext.assoc_for_value(node, value)
        assert_nil PrimitiveContext.assoc_for_value(node, node)
      end

      def test_hash_containing
        node = call("items << { x: 0, nested: { y: 1 } }")
        hashes = PrimitiveContext.hashes(node)
        nested_key = node.arguments.arguments.first.elements.last.value.elements.first.key

        assert_equal hashes.first, PrimitiveContext.hash_containing(hashes, nested_key)
      end

      private

      def call(source)
        expression(source)
      end

      def hash(source)
        call(source).arguments.arguments.first
      end

      def expression(source)
        statements = Prism.parse(source).value.statements.body
        first = statements.first
        first.is_a?(Prism::DefNode) ? first.body.body.first : first
      end

      def registry_with_schemas
        load_registry({"metadata.yml" => METADATA, "schemas.yml" => SCHEMAS})
      end
    end
  end
end
