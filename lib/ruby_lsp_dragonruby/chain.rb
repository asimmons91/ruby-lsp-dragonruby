# frozen_string_literal: true

require "prism"

module RubyLsp
  module Dragonruby
    # Helpers for reading half-typed call chains out of Prism's error recovery.
    module Chain
      # Reserved words cannot be curated DragonRuby members. When Prism
      # recovers a trailing dot by consuming a keyword as the message, the user
      # is completing at the dot, not typing the keyword as a name.
      KEYWORDS = %w[
        __ENCODING__ __FILE__ __LINE__ BEGIN END alias and begin break case class def defined? do
        else elsif end ensure false for if in module next nil not or redo rescue retry return
        self super then true undef unless until when while yield
      ].freeze

      module_function

      # Returns the receiver node to complete on and the text typed after its
      # call operator, or nil when the node is not a member call with a
      # receiver.
      def target(node)
        return unless node.is_a?(Prism::CallNode)
        return unless node.receiver

        [node.receiver, filter(node)]
      end

      # Completion can only be requested on the message the user is typing.
      # Calls with arguments, parentheses, or blocks locate the cursor
      # somewhere past the message (for example, inside a primitive hash), so
      # they are not completion targets.
      def completable?(node)
        return false unless target(node)
        return true if trailing_dot?(node)

        node.arguments.nil? && node.opening_loc.nil? && node.block.nil?
      end

      # A trailing dot is recovered by Prism as a call whose message is the
      # next token in the source (`args.` followed by `end` becomes
      # `args.end`). The message then starts on a later line than the call
      # operator, or is empty when nothing follows. A later-line identifier is
      # a valid multi-line chain continuation (`args.inputs.` followed by
      # `keyboard` becomes a normal call with `keyboard` as the message), so it
      # stays a completion filter.
      def trailing_dot?(node)
        operator = node.call_operator_loc
        message = node.message_loc
        return false unless operator && message
        return true if message.start_offset == message.end_offset

        message.start_line > operator.end_line && KEYWORDS.include?(node.name.to_s)
      end

      def filter(node)
        trailing_dot?(node) ? "" : node.name.to_s
      end
    end
  end
end
