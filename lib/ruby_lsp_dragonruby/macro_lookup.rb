# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    # Answers whether a class or module (or one of its indexed ancestors)
    # calls a class macro such as `attr_gtk`.
    #
    # The indexing enhancement tags every generated accessor with an invisible
    # comment sentinel, which lets this lookup walk the ancestors through
    # Ruby LSP's index without owning any state of its own.
    module MacroLookup
      module_function

      def applied?(index, macro, context)
        return false unless index
        return false unless context.respond_to?(:nesting)

        namespace = namespace_name(context)
        return false unless namespace

        macro.accessors.any? do |accessor|
          index.method_completion_candidates(accessor.name, namespace).any? do |entry|
            entry.comments&.include?(macro.comment_tag)
          end
        end
      rescue RubyIndexer::Index::NonExistingNamespaceError
        false
      end

      def namespace_name(context)
        nesting = context.nesting
        return nil unless nesting.is_a?(Array)

        parts = nesting.reject { |name| name.include?("<Class:") }
        return nil if parts.empty?

        parts.join("::")
      end
    end
  end
end
