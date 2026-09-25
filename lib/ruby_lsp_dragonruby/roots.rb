# frozen_string_literal: true

require "prism"

require_relative "macro_lookup"

module RubyLsp
  module Dragonruby
    # Recognizes expressions whose DragonRuby type is known without inference.
    #
    # The default rules cover the `args` parameter, the `$gtk`/`$args` globals,
    # curated top-level constants, and accessors provided by class macros such
    # as `attr_gtk`. Later milestones append strategies (for example local
    # aliases) without touching the resolver's chain logic.
    class Roots
      PARAMETERS = {"args" => "GTK::Args"}.freeze
      GLOBALS = {
        "$gtk" => "GTK::Runtime",
        "$args" => "GTK::Args"
      }.freeze

      class Strategy
        def initialize(registry, index: nil)
          @registry = registry
          @index = index
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

      # Resolves calls to accessors provided by a class macro (`outputs`,
      # `state`, ...) inside a class or module that calls the macro. The macro
      # marker method is registered in Ruby LSP's index by the indexing
      # enhancement, which makes ancestor lookups work for subclasses too.
      class MacroAccessor < Strategy
        def resolve(node, context)
          name = accessor_name(node)
          return unless name

          macro = applied_macro(name, context)
          return unless macro

          type_for_accessor(macro.accessor(name))
        end

        private

        def accessor_name(node)
          return unless node.is_a?(Prism::CallNode)
          return if node.receiver && !node.receiver.is_a?(Prism::SelfNode)

          name = node.name.to_s
          name.empty? ? nil : name
        end

        # Several macros may declare the same accessor name; the applied one
        # wins.
        def applied_macro(name, context)
          @registry.macros.each_value.find do |macro|
            macro.accessor?(name) && macro_applied?(macro, context)
          end
        end

        def macro_applied?(macro, context)
          MacroLookup.applied?(@index, macro, context)
        end

        def type_for_accessor(accessor)
          names = accessor.returns.names
          return nil if accessor.returns.unknown? || names.size != 1

          type_for(names.first)
        end
      end

      DEFAULT_STRATEGIES = [Parameter, Global, RegistryConstant, MacroAccessor].freeze

      def initialize(registry, index: nil, strategies: DEFAULT_STRATEGIES)
        @strategies = strategies.map { |strategy| strategy.new(registry, index: index) }
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
