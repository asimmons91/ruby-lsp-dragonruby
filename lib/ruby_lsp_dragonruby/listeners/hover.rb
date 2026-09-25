# frozen_string_literal: true

require "ruby_lsp/internal"

require_relative "../resolver"
require_relative "../signature"

module RubyLsp
  module Dragonruby
    module Listeners
      # Shows curated documentation for DragonRuby members and roots.
      class Hover
        include Requests::Support::Common

        def initialize(response_builder, registry, node_context, dispatcher, logger: nil)
          @response_builder = response_builder
          @node_context = node_context
          @logger = logger
          @resolver = Resolver.new(registry)

          dispatcher.register(
            self,
            :on_call_node_enter,
            :on_global_variable_read_node_enter,
            :on_local_variable_read_node_enter,
            :on_constant_read_node_enter,
            :on_constant_path_node_enter
          )
        end

        def on_call_node_enter(node)
          handle_member(node)
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
          return unless node.receiver

          resolution = @resolver.resolve(node.receiver, @node_context)
          return unless resolution.resolved_type?

          member = resolution.type.member(node.name.to_s)
          return unless member

          push_member(member)
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
