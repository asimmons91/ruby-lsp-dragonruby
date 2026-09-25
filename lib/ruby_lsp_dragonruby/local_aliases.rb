# frozen_string_literal: true

require "prism"

module RubyLsp
  module Dragonruby
    # Finds the assignment that gives a local variable its value at a read,
    # following Ruby's lexical scoping.
    #
    # The enclosing scopes come from the node context's nesting nodes, which
    # Ruby LSP does not expose publicly in the pinned range. They are read
    # defensively: when the shape changes, alias resolution degrades to
    # nothing instead of raising.
    class LocalAliases
      # A hard scope starts a fresh set of locals; blocks and lambdas inherit
      # from their enclosing scope.
      HARD_SCOPES = [
        Prism::DefNode,
        Prism::ClassNode,
        Prism::ModuleNode,
        Prism::SingletonClassNode,
        Prism::ProgramNode
      ].freeze
      SOFT_SCOPES = [Prism::BlockNode, Prism::LambdaNode].freeze
      SCOPE_NODES = (HARD_SCOPES + SOFT_SCOPES).freeze
      WRITES = [
        Prism::LocalVariableWriteNode,
        Prism::LocalVariableOrWriteNode,
        Prism::LocalVariableAndWriteNode,
        Prism::LocalVariableOperatorWriteNode,
        Prism::LocalVariableTargetNode
      ].freeze
      SHADOW = :shadow

      # Returns the nearest visible assignment node for a local variable read,
      # or nil when the variable has no visible assignment or is shadowed by a
      # block parameter or block-local.
      def assignment_for(read, context)
        return nil unless read.is_a?(Prism::LocalVariableReadNode)

        scopes = scope_chain(read, context)
        return nil if scopes.empty?

        offset = read.location.start_offset
        events = scopes.flat_map { |scope| events_for(scope, scopes) }
        nearest = events
          .select { |name, event_offset, _| name == read.name && event_offset < offset }
          .max_by { |_, event_offset, _| event_offset }
        return nil if nearest.nil? || nearest.last == SHADOW

        nearest.last
      end

      private

      # The lexical scopes containing the read, from outermost to innermost.
      # Locals do not cross a hard scope boundary, so the chain stops at the
      # innermost hard scope.
      def scope_chain(read, context)
        nodes = context&.instance_variable_get(:@nesting_nodes)
        return [] unless nodes.is_a?(Array)

        offset = read.location.start_offset
        covering = nodes.select do |node|
          node.is_a?(Prism::Node) &&
            node.location.start_offset <= offset &&
            node.location.end_offset >= offset
        end

        chain = []
        covering.reverse_each do |node|
          chain.unshift(node)
          break if hard_scope?(node)
        end
        chain
      end

      def events_for(scope, chain)
        events = []
        walk(body_of(scope), chain[chain.index(scope) + 1], events)
        events
      end

      # Collects writes from a scope's own statements, without crossing into
      # nested scopes that are not on the chain. The next scope on the chain is
      # entered so its block parameters can shadow outer locals.
      def walk(node, next_scope, events)
        return unless node

        if scope_node?(node)
          return unless node.equal?(next_scope)

          add_shadow_events(node, events) if soft_scope?(node)
        end

        events << [node.name, node.location.start_offset, node] if write?(node)
        node.child_nodes.each { |child| walk(child, next_scope, events) }
      end

      def add_shadow_events(scope, events)
        parameters = scope.parameters
        return unless parameters

        parameter_names(parameters).each do |name|
          events << [name, scope.location.start_offset, SHADOW]
        end
      end

      def parameter_names(block_parameters)
        if block_parameters.is_a?(Prism::NumberedParametersNode)
          return (1..block_parameters.maximum).map { |index| :"_#{index}" }
        end

        names = block_parameters.respond_to?(:locals) ? block_parameters.locals.map(&:name) : []
        parameters = block_parameters.respond_to?(:parameters) ? block_parameters.parameters : block_parameters
        return names unless parameters.respond_to?(:requireds)

        nodes = [
          *parameters.requireds,
          *parameters.optionals,
          parameters.rest,
          *parameters.posts,
          *parameters.keywords,
          parameters.keyword_rest,
          parameters.block
        ].compact
        names + nodes.flat_map { |node| names_for(node) }
      end

      # Destructured parameters nest their names in multi-target and splat
      # nodes.
      def names_for(node)
        case node
        when Prism::MultiTargetNode
          [*node.lefts, node.rest, *node.rights].compact.flat_map { |child| names_for(child) }
        when Prism::SplatNode
          node.expression ? names_for(node.expression) : []
        else
          (node.respond_to?(:name) && node.name) ? [node.name] : []
        end
      end

      def body_of(scope)
        return scope.statements if scope.is_a?(Prism::ProgramNode)

        scope.body if scope.respond_to?(:body)
      end

      def scope_node?(node)
        SCOPE_NODES.any? { |klass| node.is_a?(klass) }
      end

      def hard_scope?(node)
        HARD_SCOPES.any? { |klass| node.is_a?(klass) }
      end

      def soft_scope?(node)
        SOFT_SCOPES.any? { |klass| node.is_a?(klass) }
      end

      def write?(node)
        WRITES.any? { |klass| node.is_a?(klass) }
      end
    end
  end
end
