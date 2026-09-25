# frozen_string_literal: true

require "prism"

module RubyLsp
  module Dragonruby
    # Detects hash literals that are being pushed into a DragonRuby output
    # collection, and answers questions about the schema keys they accept.
    #
    # Ruby LSP's completion and hover add-on listeners do not receive the
    # cursor position, so key/value positions are inferred from the hash's
    # AST shape: an unclosed hash with a trailing comma is a key position,
    # while an unclosed hash ending in an association is a value position.
    class PrimitiveContext
      APPEND_METHODS = ["<<", "push", "concat"].freeze
      MARKER_KEY = "primitive_marker"

      class << self
        def append?(node)
          node.is_a?(Prism::CallNode) && node.receiver && APPEND_METHODS.include?(node.name.to_s)
        end

        # The primitive schemas accepted by the append call's receiver, or nil
        # when the call is not a confidently resolved primitive append.
        def schemas(registry, call_node, resolver, node_context)
          return unless append?(call_node)

          resolution = resolver.resolve(call_node.receiver, node_context)
          return unless resolution.resolved_type?

          schemas = registry.primitive_schemas_for(resolution.type)
          schemas.empty? ? nil : schemas
        end

        # Every hash literal argument of an append call, including hashes
        # inside an array literal argument.
        def hashes(call_node)
          Array(call_node.arguments&.arguments).flat_map do |argument|
            case argument
            when Prism::HashNode
              [argument]
            when Prism::ArrayNode
              argument.elements.select { |element| element.is_a?(Prism::HashNode) }
            else
              []
            end
          end
        end

        def hash_containing(hashes, node)
          location = node.location
          hashes.find do |hash|
            hash.location.start_offset <= location.start_offset &&
              hash.location.end_offset >= location.end_offset
          end
        end

        def unclosed?(hash)
          closing = hash.closing_loc
          closing.nil? || closing.length.zero?
        end

        # Prism's location for an unclosed hash ends after the last token, so
        # a gap before the location end means the user typed a trailing comma.
        def trailing_comma?(hash)
          last = hash.elements.last
          return false unless last

          hash.location.end_offset > last.location.end_offset
        end

        # The association whose value contains the node, when Prism resolves a
        # half-typed value (for example `x:`) to an implicit call node.
        def assoc_for_value(hash, node)
          location = node.location
          hash.elements.find do |element|
            next false unless element.is_a?(Prism::AssocNode)

            value = element.value
            value.location.start_offset <= location.start_offset &&
              value.location.end_offset >= location.end_offset
          end
        end

        def existing_keys(hash)
          hash.elements.filter_map do |element|
            next unless element.is_a?(Prism::AssocNode)

            key_name(element.key)
          end.to_set
        end

        def marker_value(hash)
          element = hash.elements.find do |candidate|
            candidate.is_a?(Prism::AssocNode) && key_name(candidate.key) == MARKER_KEY
          end
          value = element&.value

          value.value.to_s if value.is_a?(Prism::SymbolNode)
        end

        # When a generic collection accepts several schemas, a
        # `primitive_marker` value narrows the selection to that schema.
        def restricted_schemas(schemas, hash)
          marker = marker_value(hash)
          return schemas unless marker

          matching = schemas.select { |schema| schema.primitive_marker == marker }
          matching.empty? ? schemas : matching
        end

        # Returns [:key, nil, nil] or [:value, key_name, value_node].
        #
        # Error recovery can produce an association with a nil key when a
        # keyword follows an unclosed hash (`{ ` before `end`), which is a key
        # position, not a value position.
        def position(hash)
          last = hash.elements.last
          return [:key, nil, nil] unless last.is_a?(Prism::AssocNode)
          return [:key, nil, nil] if trailing_comma?(hash)

          key = key_name(last.key)
          return [:key, nil, nil] if key.nil? || key.empty?

          [:value, key, last.value]
        end

        def key_name(node)
          case node
          when Prism::SymbolNode
            node.value.to_s
          when Prism::StringNode
            node.unescaped.to_s
          end
        end

        # Maps a key name to an array of [PrimitiveKey, PrimitiveSchema] pairs,
        # so union contexts can label each item with its schema(s).
        def keys_by_name(schemas)
          keys = {}
          schemas.each do |schema|
            schema.keys.each do |key|
              (keys[key.name] ||= []) << [key, schema]
            end
          end
          keys
        end

        def allowed_values(keys_by_name, name)
          pairs = keys_by_name[name] || []
          pairs.flat_map { |key, _schema| Array(key.allowed_values) }.uniq
        end
      end
    end
  end
end
