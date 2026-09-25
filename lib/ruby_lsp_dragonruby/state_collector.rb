# frozen_string_literal: true

require "prism"
require "ruby_lsp/internal"

require_relative "state_store"

module RubyLsp
  module Dragonruby
    # Collects `args.state` writes from a parsed document.
    #
    # It recognizes `args.state.<path> ||= <expr>` (`CallOrWriteNode`) and
    # `args.state.<path> = <expr>` (`CallNode` attribute writes), including the
    # same forms through `attr_gtk` accessors and M4 local aliases. Reads are
    # never recorded (REQ-M5-06). Nested paths create intermediate nodes
    # (REQ-M5-02) and hash literal symbol keys become child paths (REQ-M5-05).
    class StateCollector
      SCOPE_NODES = [
        Prism::ProgramNode,
        Prism::ClassNode,
        Prism::ModuleNode,
        Prism::SingletonClassNode,
        Prism::DefNode,
        Prism::BlockNode,
        Prism::LambdaNode
      ].freeze

      def initialize(registry, resolver)
        @registry = registry
        @resolver = resolver
      end

      # Returns StateStore::Record values for every state write in the program.
      def collect(program, uri = nil)
        @resolver.reset_aliases!
        records = []
        walk(program, [], nil, uri, records)
        records
      end

      # The structural state path a node reads, if any. Hover uses this to
      # locate writes even when a middle segment collides with a curated
      # entity member (`args.state.player.x.y`).
      def state_path_for(node, context)
        nesting = context&.instance_variable_get(:@nesting_nodes)
        scopes = nesting.is_a?(Array) ? nesting.select { |candidate| scopes?(candidate) } : []
        state_path_of(node, scopes)
      end

      private

      def walk(node, scopes, parent, uri, records)
        return unless node

        scopes += [node] if scopes?(node)

        if node.is_a?(Prism::CallOrWriteNode)
          collect_write(node.receiver, node.read_name.to_s, :initialization, node.value, node.message_loc,
            scopes, uri, records)
        elsif node.is_a?(Prism::CallNode) && node.attribute_write?
          name = node.name.to_s.delete_suffix("=")
          value = node.arguments&.arguments&.first
          collect_write(node.receiver, name, :assignment, value, node.message_loc, scopes, uri, records)
        end

        node.child_nodes.each { |child| walk(child, scopes, node, uri, records) }
      end

      def collect_write(receiver, name, kind, value, message_loc, scopes, uri, records)
        return if name.nil? || name.empty? || name == "[]"

        base = state_path_of(receiver, scopes)
        return unless base

        path = base.empty? ? name : "#{base}.#{name}"
        type_name = infer_type(value, scopes)
        site = site_for(uri, message_loc, kind, type_name)

        add_intermediates(path, site, records)
        records << StateStore::Record.new(path: path, parent: parent_of(path), site: site)

        collect_hash_children(path, value, site, scopes, uri, records) if value.is_a?(Prism::HashNode)
      end

      # Intermediate nodes are entities that hold the nested path, so they get
      # the entity type and the nested write's site (REQ-M5-02).
      def add_intermediates(path, site, records)
        segments = path.split(".")
        return if segments.size < 2

        entity_name = @registry.entity_type&.name || Registry::UNKNOWN
        intermediate_site = StateStore::WriteSite.new(
          uri: site.uri,
          line: site.line,
          character: site.character,
          end_line: site.end_line,
          end_character: site.end_character,
          kind: site.kind,
          type_name: entity_name
        )

        (1...segments.size).each do |i|
          intermediate = segments[0...i].join(".")
          records << StateStore::Record.new(path: intermediate, parent: parent_of(intermediate), site: intermediate_site)
        end
      end

      def collect_hash_children(path, hash, site, scopes, uri, records)
        hash.elements.each do |element|
          next unless element.is_a?(Prism::AssocNode)

          name = key_name(element.key)
          next unless name

          child_path = "#{path}.#{name}"
          child_site = site_for(uri, element.key.location, site.kind, infer_type(element.value, scopes))
          records << StateStore::Record.new(path: child_path, parent: path, site: child_site)

          if element.value.is_a?(Prism::HashNode)
            collect_hash_children(child_path, element.value, child_site, scopes, uri, records)
          end
        end
      end

      # Resolves the chain's state anchor: it walks inward until a node resolves
      # to the state root or to a state path, then appends the outer segments.
      # This is structural on purpose, so a segment that collides with a
      # curated entity member (`x`, `y`) does not stop collection.
      def state_path_of(node, scopes)
        return nil unless node

        unless node.is_a?(Prism::CallNode) || node.is_a?(Prism::ParenthesesNode)
          return state_base(node, scopes)
        end

        segments = []
        current = unwrap(node)

        while current.is_a?(Prism::CallNode)
          resolution = @resolver.resolve(current, node_context(current, scopes))
          if resolution.state_path?
            return append(resolution.state_path, segments)
          elsif resolution.resolved_type? && @registry.state_type?(resolution.type)
            return segments.join(".")
          end

          break unless current.receiver

          segments.unshift(current.name.to_s)
          current = unwrap(current.receiver)
        end

        nil
      end

      def state_base(node, scopes)
        resolution = @resolver.resolve(node, node_context(node, scopes))
        return resolution.state_path if resolution.state_path?
        return "" if resolution.resolved_type? && @registry.state_type?(resolution.type)

        nil
      end

      def unwrap(node)
        if node.is_a?(Prism::ParenthesesNode)
          body = node.body
          return body.body.first if body.is_a?(Prism::StatementsNode) && body.body.size == 1
        end
        node
      end

      def append(base, segments)
        return base if segments.empty?

        base.empty? ? segments.join(".") : "#{base}.#{segments.join(".")}"
      end

      def infer_type(value, scopes)
        return Registry::UNKNOWN unless value

        case value
        when Prism::IntegerNode then "Integer"
        when Prism::FloatNode then "Float"
        when Prism::StringNode, Prism::InterpolatedStringNode then "String"
        when Prism::SymbolNode then "Symbol"
        when Prism::TrueNode, Prism::FalseNode then "Boolean"
        when Prism::ArrayNode then "Array"
        when Prism::HashNode then "Hash"
        else
          resolution = @resolver.resolve(value, node_context(value, scopes))
          return resolution.type.name if resolution.resolved_type?
          return resolution.core_type if resolution.core?

          Registry::UNKNOWN
        end
      end

      def node_context(node, scopes)
        RubyLsp::NodeContext.new(node, nil, scopes, nil)
      end

      def site_for(uri, location, kind, type_name)
        StateStore::WriteSite.new(
          uri: uri&.to_s,
          line: location.start_line - 1,
          character: location.start_column,
          end_line: location.end_line - 1,
          end_character: location.end_column,
          kind: kind,
          type_name: type_name
        )
      end

      def key_name(node)
        case node
        when Prism::SymbolNode then node.value.to_s
        when Prism::StringNode then node.unescaped.to_s
        end
      end

      def parent_of(path)
        path.include?(".") ? path.rpartition(".").first : ""
      end

      def scopes?(node)
        SCOPE_NODES.any? { |klass| node.is_a?(klass) }
      end
    end
  end
end
