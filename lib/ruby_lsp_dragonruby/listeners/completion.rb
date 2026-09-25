# frozen_string_literal: true

require "ruby_lsp/internal"

require_relative "../chain"
require_relative "../resolution"
require_relative "../resolver"
require_relative "../signature"

module RubyLsp
  module Dragonruby
    module Listeners
      # Offers curated members after a confidently resolved DragonRuby
      # receiver.
      class Completion
        include Requests::Support::Common

        def initialize(response_builder, registry, node_context, dispatcher, _uri, logger: nil)
          @response_builder = response_builder
          @node_context = node_context
          @logger = logger
          @resolver = Resolver.new(registry)

          dispatcher.register(self, :on_call_node_enter)
        end

        def on_call_node_enter(node)
          handle(node)
        rescue => error
          log(error)
        end

        private

        def handle(node)
          return unless Chain.completable?(node)

          receiver, filter = Chain.target(node)
          resolution = @resolver.resolve(receiver, @node_context)
          return unless resolution.resolved_type?

          range = edit_range(node)
          return unless range

          push_members(resolution.type, filter, range)
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

        def edit_range(node)
          if Chain.trailing_dot?(node)
            operator = node.call_operator_loc
            position = Interface::Position.new(line: operator.end_line - 1, character: operator.end_column)
            Interface::Range.new(start: position, end: position)
          else
            range_from_location(node.message_loc)
          end
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

        def log(error)
          @logger&.error("#{error.class}: #{error.message}")
        end
      end
    end
  end
end
