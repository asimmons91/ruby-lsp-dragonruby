# frozen_string_literal: true

require "prism"

module RubyLsp
  module Dragonruby
    # Recognizes expressions whose DragonRuby type is known without inference.
    #
    # The default rules cover the `args` parameter, the `$gtk`/`$args` globals,
    # and curated top-level constants. Later milestones append strategies (for
    # example `attr_gtk` accessors or local aliases) without touching the
    # resolver's chain logic.
    class Roots
      PARAMETERS = {"args" => "GTK::Args"}.freeze
      GLOBALS = {
        "$gtk" => "GTK::Runtime",
        "$args" => "GTK::Args"
      }.freeze

      class Strategy
        def initialize(registry)
          @registry = registry
        end

        def resolve(_node, _context)
          nil
        end

        private

        def type_for(name)
          @registry.type(name)
        end
      end

      class Parameter < Strategy
        def resolve(node, _context)
          return unless node.is_a?(Prism::LocalVariableReadNode)

          type_for(PARAMETERS[node.name.to_s])
        end
      end

      class Global < Strategy
        def resolve(node, _context)
          return unless node.is_a?(Prism::GlobalVariableReadNode)

          type_for(GLOBALS[node.name.to_s])
        end
      end

      class RegistryConstant < Strategy
        def resolve(node, _context)
          name = constant_name(node)
          name && type_for(name)
        end

        private

        def constant_name(node)
          case node
          when Prism::ConstantReadNode
            node.name.to_s
          when Prism::ConstantPathNode
            node.full_name
          end
        rescue Prism::ConstantPathNode::MissingNodesInConstantPathError,
          Prism::ConstantPathNode::DynamicPartsInConstantPathError
          nil
        end
      end

      DEFAULT_STRATEGIES = [Parameter, Global, RegistryConstant].freeze

      def initialize(registry, strategies: DEFAULT_STRATEGIES)
        @strategies = strategies.map { |strategy| strategy.new(registry) }
      end

      def resolve(node, context = nil)
        @strategies.each do |strategy|
          type = strategy.resolve(node, context)
          return type if type
        end

        nil
      end
    end
  end
end
