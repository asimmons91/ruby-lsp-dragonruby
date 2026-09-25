# frozen_string_literal: true

require "prism"
require "ruby_lsp/internal"

require_relative "../chain"
require_relative "../edit_distance"
require_relative "../primitive_context"
require_relative "../resolver"
require_relative "../settings"
require_relative "undefined_member"

module RubyLsp
  module Dragonruby
    module Warnings
      # One AST walk that produces the add-on's diagnostics: undefined members
      # (REQ-M7-01..04), unknown primitive hash keys (REQ-M7-05), and reads of
      # state paths that are never written (REQ-M7-06).
      #
      # The walk tracks scope nodes the same way `StateCollector` does, so
      # `attr_gtk` accessors and M4 local aliases resolve unchanged.
      class Analyzer
        SCOPE_NODES = [
          Prism::ProgramNode,
          Prism::ClassNode,
          Prism::ModuleNode,
          Prism::SingletonClassNode,
          Prism::DefNode,
          Prism::BlockNode,
          Prism::LambdaNode
        ].freeze

        SOURCE = "dragonruby"

        def initialize(registry, index: nil, state: nil, settings: nil, logger: nil)
          @registry = registry
          @index = index
          @state = state
          @settings = settings || Settings.new
          @logger = logger
          @resolver = state&.resolver || Resolver.new(registry, index: index, state_store: state&.store)
          @undefined = UndefinedMember.new(registry, index: index, settings: @settings)
        end

        # Returns `Interface::Diagnostic` values for the parsed program.
        def diagnostics(program)
          return [] unless program
          return [] unless @settings.enabled?

          @resolver.reset_aliases!
          diagnostics = []
          walk(program, [], diagnostics)
          diagnostics
        rescue => error
          log(error)
          []
        end

        private

        def walk(node, scopes, diagnostics)
          return unless node

          scopes += [node] if scope?(node)

          if node.is_a?(Prism::CallNode)
            context = node_context(node, scopes)
            collect_undefined_member(node, context, diagnostics)
            collect_primitive_keys(node, context, diagnostics)
            collect_unassigned_state_read(node, context, diagnostics)
          end

          node.child_nodes.each { |child| walk(child, scopes, diagnostics) }
        end

        # REQ-M7-01: a confident registry receiver whose member is missing from
        # the registry, Ruby LSP's index, and stock Ruby.
        def collect_undefined_member(node, context, diagnostics)
          return if node.attribute_write? || Chain.trailing_dot?(node)

          name = node.name.to_s
          return if name.empty?

          resolution = @resolver.resolve(node.receiver, context)
          return unless resolution.resolved_type?

          message = @undefined.warning_for(resolution.type, name)
          return unless message

          location = node.message_loc
          return unless location&.length&.positive?

          diagnostics << diagnostic(location, message, Constant::DiagnosticSeverity::WARNING)
        end

        # REQ-M7-05: keys in a primitive hash that no accepted schema defines.
        # Unclosed hashes are skipped so typing a key does not nag.
        def collect_primitive_keys(node, context, diagnostics)
          return unless @settings.primitive_keys?
          return unless PrimitiveContext.append?(node)

          schemas = PrimitiveContext.schemas(@registry, node, @resolver, context)
          return unless schemas

          PrimitiveContext.hashes(node).each do |hash|
            next if PrimitiveContext.unclosed?(hash)

            restricted = PrimitiveContext.restricted_schemas(schemas, hash)
            keys = PrimitiveContext.keys_by_name(restricted)

            hash.elements.each do |element|
              next unless element.is_a?(Prism::AssocNode)

              name = PrimitiveContext.key_name(element.key)
              next if name.nil? || name.empty? || name == PrimitiveContext::MARKER_KEY
              next if keys.key?(name) || @settings.allowlist.include?(name)

              message = primitive_key_message(name, restricted)
              diagnostics << diagnostic(element.key.location, message, Constant::DiagnosticSeverity::HINT)
            end
          end
        end

        # REQ-M7-06: reads that resolve to a state path with no write sites.
        # Only runs after the workspace scan, so an unindexed workspace never
        # produces false positives.
        def collect_unassigned_state_read(node, context, diagnostics)
          return unless @settings.unassigned_state_reads?
          return unless @state&.scanned?
          return if node.attribute_write? || Chain.trailing_dot?(node)

          resolution = @resolver.resolve(node, context)
          return unless resolution.state_path?

          path = resolution.state_path
          return if path.nil? || path.empty? || @state.path?(path)

          location = node.message_loc
          return unless location&.length&.positive?

          message = "State path `#{path}` is read but has no write sites in this workspace."
          diagnostics << diagnostic(location, message, Constant::DiagnosticSeverity::HINT)
        end

        def primitive_key_message(name, schemas)
          subjects = schemas.map(&:name)
          subject = (subjects.size == 1) ? "the #{subjects.first} primitive" : "the #{subjects.join(", ")} primitives"
          text = "`#{name}` is not a known key of #{subject} in DragonRuby #{version}."
          candidates = schemas.flat_map { |schema| schema.keys.map(&:name) }
          suggestion = EditDistance.suggestion(name, candidates)
          text += " Did you mean `#{suggestion}`?" if suggestion
          text
        end

        def diagnostic(location, message, severity)
          Interface::Diagnostic.new(
            range: Interface::Range.new(
              start: Interface::Position.new(line: location.start_line - 1, character: location.start_column),
              end: Interface::Position.new(line: location.end_line - 1, character: location.end_column)
            ),
            message: message,
            severity: severity,
            source: SOURCE
          )
        end

        def node_context(node, scopes)
          RubyLsp::NodeContext.new(node, nil, scopes, nil)
        end

        def scope?(node)
          SCOPE_NODES.any? { |klass| node.is_a?(klass) }
        end

        def version
          @registry.metadata&.dragonruby_version
        end

        def log(error)
          @logger&.error("#{error.class}: #{error.message}")
        end
      end
    end
  end
end
