# frozen_string_literal: true

require "ruby_lsp/internal"

require_relative "../resolver"

module RubyLsp
  module Dragonruby
    module Listeners
      # Returns every write site of a confidently resolved `args.state` path.
      # Initializations (`||=`) come first, then assignments, in file order
      # (REQ-M5-10).
      class Definition
        def initialize(response_builder, registry, node_context, dispatcher, uri, logger: nil, index: nil, state: nil)
          @response_builder = response_builder
          @node_context = node_context
          @uri = uri
          @logger = logger
          @state = state
          @resolver = state&.resolver || Resolver.new(registry, index: index)

          state&.ensure_workspace_scanned
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
          return unless @state

          @state.refresh(@uri, @node_context)

          resolution = @resolver.resolve(node, @node_context)
          return unless resolution.state_path?

          entry = @state.entry(resolution.state_path)
          return unless entry

          sites(entry).each { |site| @response_builder << location_for(site) }
        end

        def sites(entry)
          entry.writes
            .sort_by(&:sort_key)
            .uniq { |site| [site.uri, site.line, site.character, site.kind] }
        end

        def location_for(site)
          Interface::Location.new(
            uri: site.uri.to_s,
            range: Interface::Range.new(
              start: Interface::Position.new(line: site.line, character: site.character),
              end: Interface::Position.new(line: site.end_line, character: site.end_character)
            )
          )
        end

        def log(error)
          @logger&.error("#{error.class}: #{error.message}")
        end
      end
    end
  end
end
