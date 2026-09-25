# frozen_string_literal: true

require "ruby_indexer/ruby_indexer"

module RubyLsp
  module Dragonruby
    # Registers methods for DragonRuby class macros (`attr_gtk`, `attr_sprite`,
    # ...) in Ruby LSP's index whenever a workspace file calls them.
    #
    # The enhancement reads the macro definitions from the registry configured
    # at activation. It is inert until then, so an unconfigured add-on never
    # changes the index.
    class IndexingEnhancement < RubyIndexer::Enhancement
      class << self
        attr_accessor :registry
      end

      def on_call_node_enter(node)
        return if node.receiver

        registry = self.class.registry
        return unless registry

        registry.macros_for_call_name(node.name.to_s).each do |macro|
          add_macro_methods(macro, node)
        end
      end

      private

      def add_macro_methods(macro, node)
        signatures = [RubyIndexer::Entry::Signature.new([])]

        macro.accessors.each do |accessor|
          comments = "#{macro.comment_tag}\n#{accessor.doc}"
          @listener.add_method(accessor.name, node.location, signatures, comments: comments)
        end
      end
    end
  end
end
