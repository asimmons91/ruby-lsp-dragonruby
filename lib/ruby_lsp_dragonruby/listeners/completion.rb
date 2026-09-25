# frozen_string_literal: true

require "ruby_lsp/internal"

require_relative "../chain"
require_relative "../primitive_context"
require_relative "../resolution"
require_relative "../resolver"
require_relative "../signature"
require_relative "../standard_methods"

module RubyLsp
  module Dragonruby
    module Listeners
      # Offers curated members after a confidently resolved DragonRuby
      # receiver, schema keys inside primitive hash literals, and known
      # `args.state` child paths.
      class Completion
        include Requests::Support::Common

        def initialize(response_builder, registry, node_context, dispatcher, uri, logger: nil, index: nil, state: nil)
          @response_builder = response_builder
          @registry = registry
          @node_context = node_context
          @logger = logger
          @state = state
          @resolver = state&.resolver || Resolver.new(registry, index: index)

          state&.ensure_workspace_scanned
          state&.refresh(uri, node_context) if uri
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
          return handle_bare_call(node) unless node.receiver
          return unless Chain.completable?(node)

          receiver, filter = Chain.target(node)
          resolution = @resolver.resolve(receiver, @node_context)
          return unless resolution.confident?

          range = edit_range(node)
          return unless range

          if resolution.resolved_type?
            if resolution.type.core_extension?
              scope = class_receiver?(receiver) ? :class : :instance
              push_core_extension_members(resolution.type.name, filter, range, scope: scope)
            else
              push_members(resolution.type, filter, range)
              push_state_children("", filter, range) if @registry.state_type?(resolution.type)
            end
          elsif resolution.core?
            push_core_extension_members(resolution.core_type, filter, range, scope: :instance)
          elsif resolution.state_path?
            push_state_members(resolution.state_path, filter, range)
          end
        end

        # `Kernel` helpers are callable without a receiver, so a bare call name
        # completes the curated Kernel members at an instance position.
        def handle_bare_call(node)
          return unless @registry.core_extension_type("Kernel")

          name = node.name.to_s
          return if name.empty?

          range = range_from_location(node.message_loc)
          return unless range

          push_core_extension_members("Kernel", name, range, scope: :instance)
        end

        # Core extensions resolve through the constant root strategy for class
        # receivers; macro accessors that return a core type are instance
        # receivers even though their resolution carries the extension type.
        def class_receiver?(node)
          case node
          when Prism::ConstantReadNode, Prism::ConstantPathNode
            true
          when Prism::ParenthesesNode
            body = node.body
            body.is_a?(Prism::StatementsNode) && body.body.size == 1 && class_receiver?(body.body.first)
          else
            false
          end
        end

        # A state sub-path behaves like an entity: its curated members are
        # offered alongside the known child paths (REQ-M5-08) and any core
        # extensions of its inferred types (REQ-M6-03).
        def push_state_members(path, filter, range)
          push_members(@registry.entity_type, filter, range) if @registry.entity_type
          push_state_core_extensions(path, filter, range)
          push_state_children(path, filter, range)
        end

        def push_state_core_extensions(path, filter, range)
          entry = @state&.entry(path)
          return unless entry

          offered = {}
          entry.types.each do |type_name|
            push_core_extension_members(type_name, filter, range, scope: :instance, offered: offered)
          end
        end

        # Curated additions to a core Ruby class. Stock Ruby methods are never
        # offered (REQ-M6-06), and members declare whether they apply to
        # instance or class receivers.
        def push_core_extension_members(core_name, filter, range, scope:, offered: nil)
          extension = @registry.core_extension_type(core_name)
          return unless extension

          offered ||= {}
          existing = @response_builder.response.map(&:label)

          extension.all_members.each do |member|
            next unless member.offered_for?(scope)

            member.signatures.each do |name|
              next if standard_method?(core_name, name, scope)
              next unless name.start_with?(filter)
              next if existing.include?(name) || offered[name]

              offered[name] = true
              @response_builder << build_item(member, name, range)
            end
          end

          offered
        end

        def standard_method?(core_name, name, scope)
          if scope == :class
            StandardMethods.standard_class_method?(core_name, name)
          else
            StandardMethods.standard_instance_method?(core_name, name)
          end
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

        def push_members(type, filter, range, offered = {})
          existing = @response_builder.response.map(&:label)

          type.all_members.each do |member|
            member.signatures.each do |name|
              next unless name.start_with?(filter)
              next if existing.include?(name) || offered[name]

              offered[name] = true
              @response_builder << build_item(member, name, range)
            end
          end

          offered
        end

        # The known child paths of a state root or sub-path, with their
        # inferred types (REQ-M5-08).
        def push_state_children(path, filter, range)
          return unless @state

          existing = @response_builder.response.map(&:label)
          offered = {}

          @state.child_names(path).each do |name|
            next unless name.start_with?(filter)
            next if existing.include?(name) || offered[name]

            offered[name] = true
            child_path = path.empty? ? name : "#{path}.#{name}"
            @response_builder << build_state_item(name, @state.entry(child_path), range)
          end
        end

        def build_state_item(name, entry, range)
          Interface::CompletionItem.new(
            label: name,
            filter_text: name,
            detail: entry ? entry.types.join(" | ") : "Unknown",
            label_details: Interface::CompletionItemLabelDetails.new(description: "DragonRuby state"),
            kind: Constant::CompletionItemKind::FIELD,
            documentation: Interface::MarkupContent.new(kind: Constant::MarkupKind::MARKDOWN, value: state_doc(entry)),
            text_edit: Interface::TextEdit.new(range: range, new_text: name)
          )
        end

        def state_doc(entry)
          return "" unless entry

          count = entry.write_count
          suffix = (count == 1) ? "" : "s"
          content = "#{count} write site#{suffix}."
          first = entry.first_initialization
          content << "\n\nFirst initialized at `#{first.uri}:#{first.line + 1}`." if first&.uri
          content
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
