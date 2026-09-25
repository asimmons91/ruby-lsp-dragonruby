# frozen_string_literal: true

require "ruby_lsp/internal"

require_relative "../chain"
require_relative "../primitive_context"
require_relative "../resolution"
require_relative "../resolver"
require_relative "../signature"

module RubyLsp
  module Dragonruby
    module Listeners
      # Offers curated members after a confidently resolved DragonRuby
      # receiver, and schema keys inside primitive hash literals.
      class Completion
        include Requests::Support::Common

        def initialize(response_builder, registry, node_context, dispatcher, _uri, logger: nil, index: nil)
          @response_builder = response_builder
          @registry = registry
          @node_context = node_context
          @logger = logger
          @resolver = Resolver.new(registry, index: index)

          dispatcher.register(self, :on_call_node_enter)
        end

        def on_call_node_enter(node)
          handle(node)
        rescue => error
          log(error)
        end

        private

        def handle(node)
          return unless node.is_a?(Prism::CallNode)
          return if handle_primitive(node)

          return unless Chain.completable?(node)

          receiver, filter = Chain.target(node)
          resolution = @resolver.resolve(receiver, @node_context)
          return unless resolution.resolved_type?

          range = edit_range(node)
          return unless range

          push_members(resolution.type, filter, range)
        end

        def handle_primitive(node)
          call = primitive_call(node)
          return false unless call

          schemas = PrimitiveContext.schemas(@registry, call, @resolver, @node_context)
          return false unless schemas

          if node.equal?(call)
            handle_append(schemas, call)
            true
          else
            handle_partial_key(schemas, call, node)
          end
        end

        # The append call to complete inside: the target itself, or the parent
        # call when the user is typing a key name (`{ x: 0, bl`).
        def primitive_call(node)
          return node if PrimitiveContext.append?(node)

          parent = @node_context&.parent
          return parent if parent.is_a?(Prism::CallNode) && PrimitiveContext.append?(parent)

          nil
        end

        def handle_append(schemas, call)
          hash = unclosed_hash(call)
          return unless hash

          kind, key, value = PrimitiveContext.position(hash)
          restricted = PrimitiveContext.restricted_schemas(schemas, hash)

          if kind == :value
            push_values(restricted, key, value)
          else
            push_keys(restricted, hash, filter: nil, range: hash_end_range(hash))
          end
        end

        # Returns false when the node is not inside a hash of the append call,
        # so chain completion can still handle other append arguments.
        def handle_partial_key(schemas, call, node)
          hash = PrimitiveContext.hash_containing(PrimitiveContext.hashes(call), node)
          return false unless hash

          restricted = PrimitiveContext.restricted_schemas(schemas, hash)

          # `{ x:` parses as an implicit call node for the association value:
          # the user is at the value position, not typing a key name.
          assoc = PrimitiveContext.assoc_for_value(hash, node)
          if assoc
            return push_values(restricted, PrimitiveContext.key_name(assoc.key), assoc.value)
          end

          range = range_from_location(node.message_loc || node.location)
          push_keys(restricted, hash, filter: node.name.to_s, range: range) if range
          true
        end

        def unclosed_hash(call)
          PrimitiveContext.hashes(call).find { |hash| PrimitiveContext.unclosed?(hash) }
        end

        def push_members(type, filter, range)
          existing = @response_builder.response.map(&:label)
          offered = {}

          type.all_members.each do |member|
            member.signatures.each do |name|
              next unless name.start_with?(filter)
              next if existing.include?(name) || offered[name]

              offered[name] = true
              @response_builder << build_item(member, name, range)
            end
          end
        end

        def push_keys(schemas, hash, filter:, range:)
          return unless range

          existing = @response_builder.response.map(&:label)
          present = PrimitiveContext.existing_keys(hash)
          offered = {}

          PrimitiveContext.keys_by_name(schemas).each do |name, pairs|
            next if present.include?(name)
            next unless filter.nil? || name.start_with?(filter)
            next if existing.include?(name) || offered[name]

            offered[name] = true
            @response_builder << build_key_item(name, pairs, range)
          end

          push_marker_key(schemas, present, existing, filter, range)
        end

        # A generic collection accepts several schemas, so offer
        # `primitive_marker` to pick one from its marker value.
        def push_marker_key(schemas, present, existing, filter, range)
          return unless schemas.size > 1
          return if present.include?(PrimitiveContext::MARKER_KEY)
          return if existing.include?(PrimitiveContext::MARKER_KEY)
          return if filter && !PrimitiveContext::MARKER_KEY.start_with?(filter)

          @response_builder << Interface::CompletionItem.new(
            label: PrimitiveContext::MARKER_KEY,
            filter_text: PrimitiveContext::MARKER_KEY,
            detail: "Symbol",
            label_details: Interface::CompletionItemLabelDetails.new(description: "primitive"),
            kind: Constant::CompletionItemKind::FIELD,
            documentation: Interface::MarkupContent.new(
              kind: Constant::MarkupKind::MARKDOWN,
              value: "Selects which primitive schema applies when pushing into a generic collection."
            ),
            text_edit: Interface::TextEdit.new(range: range, new_text: "#{PrimitiveContext::MARKER_KEY}: ")
          )
        end

        # Returns true when at least one allowed value was offered, so callers
        # can fall back to chain completion for keys without allowed values.
        def push_values(schemas, name, value_node)
          values =
            if name == PrimitiveContext::MARKER_KEY
              schemas.filter_map(&:primitive_marker)
            else
              PrimitiveContext.allowed_values(PrimitiveContext.keys_by_name(schemas), name)
            end
          return false if values.empty?

          range = value_range(value_node)
          return false unless range

          partial = value_node.is_a?(Prism::SymbolNode) ? value_node.value.to_s : ""
          symbol = name == PrimitiveContext::MARKER_KEY ||
            PrimitiveContext.keys_by_name(schemas)[name]&.any? { |key, _| key.type.names.include?("Symbol") }

          pushed = false
          values.each do |value|
            next unless value.to_s.start_with?(partial)

            pushed = true
            label = symbol ? ":#{value}" : value.to_s
            @response_builder << Interface::CompletionItem.new(
              label: label,
              filter_text: label,
              kind: Constant::CompletionItemKind::ENUM_MEMBER,
              text_edit: Interface::TextEdit.new(range: range, new_text: label)
            )
          end

          pushed
        end

        def build_item(member, label, range)
          Interface::CompletionItem.new(
            label: label,
            filter_text: label,
            detail: member.returns.to_s,
            label_details: Interface::CompletionItemLabelDetails.new(description: "DragonRuby"),
            kind: kind_for(member),
            documentation: Interface::MarkupContent.new(kind: Constant::MarkupKind::MARKDOWN, value: doc_for(member)),
            text_edit: Interface::TextEdit.new(range: range, new_text: label)
          )
        end

        def build_key_item(name, pairs, range)
          key, = pairs.first
          schema_names = pairs.map { |_key, schema| schema.name }.uniq

          Interface::CompletionItem.new(
            label: name,
            filter_text: name,
            detail: key_detail(key, schema_names),
            label_details: Interface::CompletionItemLabelDetails.new(description: schema_names.join(", ")),
            kind: Constant::CompletionItemKind::FIELD,
            documentation: Interface::MarkupContent.new(kind: Constant::MarkupKind::MARKDOWN, value: key.doc.to_s),
            text_edit: Interface::TextEdit.new(range: range, new_text: "#{name}: ")
          )
        end

        def key_detail(key, schema_names)
          detail = key.type.to_s
          detail += " = #{key.default.inspect}" if key.default?
          detail += " (#{schema_names.join(", ")})" if schema_names.size > 1
          detail
        end

        def kind_for(member)
          if member.method?
            Constant::CompletionItemKind::METHOD
          else
            Constant::CompletionItemKind::PROPERTY
          end
        end

        def doc_for(member)
          content = +member.doc.to_s
          content << "\n\n[DragonRuby docs](#{member.docs_url})" if member.docs_url
          content
        end

        def edit_range(node)
          if Chain.trailing_dot?(node)
            operator = node.call_operator_loc
            position = Interface::Position.new(line: operator.end_line - 1, character: operator.end_column)
            Interface::Range.new(start: position, end: position)
          else
            range_from_location(node.message_loc)
          end
        end

        def hash_end_range(hash)
          closing = hash.closing_loc
          return unless closing

          position = Interface::Position.new(line: closing.start_line - 1, character: closing.start_column)
          Interface::Range.new(start: position, end: position)
        end

        # Prism wraps a half-typed `key:` value in an implicit node whose
        # location covers the key and colon. The insertion point is after it.
        def value_range(value_node)
          return range_from_location(value_node.location) unless value_node.is_a?(Prism::ImplicitNode)

          location = value_node.location
          position = Interface::Position.new(line: location.end_line - 1, character: location.end_column)
          Interface::Range.new(start: position, end: position)
        end

        def log(error)
          @logger&.error("#{error.class}: #{error.message}")
        end
      end
    end
  end
end
