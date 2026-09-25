# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestChain < Minitest::Test
      def test_trailing_dot_is_detected_through_error_recovery
        node = last_expression("def tick(args)\n  args.inputs.keyboard.\nend")

        assert Chain.trailing_dot?(node)
        assert_equal "", Chain.filter(node)
      end

      def test_multiline_identifier_continuation_is_a_filter
        node = Prism.parse("def tick(args)\n  args.inputs.\n  keybo\nend").value.statements.body.first.body.body.first

        refute Chain.trailing_dot?(node)
        assert_equal "keybo", Chain.filter(node)
      end

      def test_multiline_keyword_recovery_is_a_trailing_dot
        node = Prism.parse("def tick(args)\n  args.inputs.\n  end\nend").value.statements.body.first.body.body.first

        assert Chain.trailing_dot?(node)
        assert_equal "", Chain.filter(node)
      end

      def test_empty_message_is_a_trailing_dot
        node = Prism.parse("args.inputs.").value.statements.body.last

        assert Chain.trailing_dot?(node)
      end

      def test_adjacent_message_is_not_a_trailing_dot
        node = Prism.parse("args.inputs.keyboard").value.statements.body.last

        refute Chain.trailing_dot?(node)
        assert_equal "keyboard", Chain.filter(node)
      end

      def test_partial_message_is_the_filter
        node = Prism.parse("def tick(args)\n  args.inputs.ke\nend").value.statements.body.first.body.body.first

        refute Chain.trailing_dot?(node)
        assert_equal "ke", Chain.filter(node)
      end

      def test_target_returns_receiver_and_filter
        node = Prism.parse("def tick(args)\n  args.inputs.ke\nend").value.statements.body.first.body.body.first
        receiver, filter = Chain.target(node)

        assert_instance_of Prism::CallNode, receiver
        assert_equal "inputs", receiver.name.to_s
        assert_equal "ke", filter
      end

      def test_target_is_nil_without_a_receiver
        assert_nil Chain.target(Prism.parse("foo").value.statements.body.first)
        assert_nil Chain.target(Prism.parse("5").value.statements.body.first)
      end

      def test_completable_requires_the_message_to_be_the_last_token
        partial = Prism.parse("def tick(args)\n  args.inputs.ke\nend").value.statements.body.first.body.body.first
        trailing = Prism.parse("def tick(args)\n  args.inputs.\nend").value.statements.body.first.body.body.first
        with_arguments = Prism.parse("args.outputs.sprites << { x: 0 }").value.statements.body.first
        with_block = Prism.parse("args.outputs.sprites.each do |sprite|\nend").value.statements.body.first

        assert Chain.completable?(partial)
        assert Chain.completable?(trailing)
        refute Chain.completable?(with_arguments)
        refute Chain.completable?(with_block)
      end

      private

      def last_expression(source)
        Prism.parse(source).value.statements.body.first.body.body.first
      end
    end
  end
end
