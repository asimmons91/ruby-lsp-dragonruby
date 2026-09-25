# frozen_string_literal: true

require "ruby_lsp/internal"

require_relative "../macro_lookup"
require_relative "../primitive_context"
require_relative "../resolver"
require_relative "../signature"

module RubyLsp
  module Dragonruby
    module Listeners
      # Shows curated documentation for DragonRuby members, roots, primitive
      # hash keys, and class macro accessors.
      class Hover
        include Requests::Support::Common

        def initialize(response_builder, registry, node_context, dispatcher, logger: nil, index: nil, state: nil)
          @response_builder = response_builder
          @registry = registry
          @node_context = node_context
          @logger = logger
          @index = index
          @state = state
          @resolver = state&.resolver || Resolver.new(registry, index: index)

          state&.ensure_workspace_scanned
          dispatcher.register(
            self,
            :on_call_node_enter,
            :on_global_variable_read_node_enter,
            :on_local_variable_read_node_enter,
            :on_constant_read_node_enter,
            :on_constant_path_node_enter,
            :on_symbol_node_enter,
            :on_string_node_enter
          )
        end

        def on_call_node_enter(node)
          return if handle_member(node)

          handle_macro_accessor(node)
        rescue => error
          log(error)
        end

        def on_symbol_node_enter(node)
          handle_primitive_key(node)
        rescue => error
          log(error)
        end

        def on_string_node_enter(node)
          handle_primitive_key(node)
        rescue => error
          log(error)
        end

        def on_local_variable_read_node_enter(node)
          handle_root(node, node.name.to_s)
        rescue => error
          log(error)
        end

        def on_global_variable_read_node_enter(node)
          handle_root(node, node.name.to_s)
        rescue => error
          log(error)
        end

        def on_constant_read_node_enter(node)
          handle_root(node, node.name.to_s)
        rescue => error
          log(error)
        end

        def on_constant_path_node_enter(node)
          handle_root(node, constant_path_name(node))
        rescue => error
          log(error)
        end

        private

        def handle_member(node)
          return false unless node.receiver

          resolution = @resolver.resolve(node.receiver, @node_context)

          member = resolution.type&.member(node.name.to_s)
          if member
            push_member(member)
            return true
          end

          handle_state_member(node)
        end

        # Shows the inferred types and write sites of a known state path
        # (REQ-M5-09). Writes answer first; an unwritten sub-path falls back to
        # the curated entity member of the hovered name.
        def handle_state_member(node)
          return false unless @state

          path = @state.state_path_for(node, @node_context)
          return false if path.nil? || path.empty?

          entry = @state.entry_with_context(path, @node_context)
          if entry
            push_state(path, entry)
            return true
          end

          member = @registry.entity_type&.member(node.name.to_s)
          return false unless member

          push_member(member)
          true
        end

        def handle_macro_accessor(node)
          name = macro_accessor_name(node)
          return unless name

          macro = @registry.macros.each_value.find do |candidate|
            candidate.accessor?(name) && MacroLookup.applied?(@index, candidate, @node_context)
          end
          return unless macro

          push_accessor(macro, macro.accessor(name), name)
        end

        def macro_accessor_name(node)
          return unless node.is_a?(Prism::CallNode)
          return if node.receiver && !node.receiver.is_a?(Prism::SelfNode)

          name = node.name.to_s
          name.empty? ? nil : name
        end

        def handle_primitive_key(node)
          call = @node_context&.call_node
          return unless call.is_a?(Prism::CallNode)

          schemas = PrimitiveContext.schemas(@registry, call, @resolver, @node_context)
          return unless schemas

          hash = PrimitiveContext.hash_containing(PrimitiveContext.hashes(call), node)
          return unless hash
          return unless hash.elements.any? { |element| element.is_a?(Prism::AssocNode) && element.key.equal?(node) }

          name = PrimitiveContext.key_name(node)
          return unless name

          pairs = PrimitiveContext.keys_by_name(PrimitiveContext.restricted_schemas(schemas, hash))[name]
          return unless pairs

          push_primitive_key(pairs)
        end

        def handle_root(node, label)
          return unless label

          resolution = @resolver.resolve(node, @node_context)
          return unless resolution.resolved_type?

          push_type(resolution.type, label)
        end

        def push_member(member)
          @response_builder.push(signature_block(Signature.of(member), member.returns.to_s), category: :title)

          content = +member.doc.to_s
          content << "\n\n[DragonRuby docs](#{member.docs_url})" if member.docs_url
          @response_builder.push(content, category: :documentation) unless content.empty?
        end

        def push_state(path, entry)
          @response_builder.push(signature_block(path, entry.types.join(" | ")), category: :title)

          count = entry.write_count
          suffix = (count == 1) ? "" : "s"
          content = "#{count} write site#{suffix}."
          first = entry.first_initialization
          content << "\n\nFirst initialized at `#{format_site(first)}`." if first
          @response_builder.push(content, category: :documentation)
        end

        def format_site(site)
          return "line #{site.line + 1}" unless site.uri

          "#{site.uri}:#{site.line + 1}"
        end

        def push_accessor(macro, accessor, name)
          @response_builder.push(signature_block(name, accessor.returns.to_s), category: :title)

          content = +accessor.doc.to_s
          content << "\n\nProvided by `#{macro.name}`." unless content.empty?
          @response_builder.push(content, category: :documentation) unless content.empty?
        end

        def push_primitive_key(pairs)
          key, = pairs.first
          schema_names = pairs.map { |_key, schema| schema.name }.uniq

          @response_builder.push(signature_block(key.name, key.type.to_s), category: :title)

          content = [+key.doc.to_s]
          content << "Default: #{key.default.inspect}" if key.default?
          content << "Allowed values: #{key.allowed_values.join(", ")}" if key.allowed_values
          content << "Schemas: #{schema_names.join(", ")}" if schema_names.size > 1
          @response_builder.push(content.reject(&:empty?).join("\n\n"), category: :documentation)
        end

        def push_type(type, label)
          @response_builder.push(signature_block(label, type.name), category: :title)
          @response_builder.push(type.doc, category: :documentation) if type.doc
        end

        def signature_block(left, right)
          "```ruby\n#{left} → #{right}\n```"
        end

        def constant_path_name(node)
          node.full_name
        rescue Prism::ConstantPathNode::MissingNodesInConstantPathError,
          Prism::ConstantPathNode::DynamicPartsInConstantPathError
          nil
        end

        def log(error)
          @logger&.error("#{error.class}: #{error.message}")
        end
      end
    end
  end
end
