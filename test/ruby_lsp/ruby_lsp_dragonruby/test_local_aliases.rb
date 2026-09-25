# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestLocalAliases < Minitest::Test
      include NodeContextHelper

      def setup
        @aliases = LocalAliases.new
      end

      def test_returns_nil_without_a_context
        read = last_statement("def tick(args)\n  kb = args.inputs\n  kb\nend")

        assert_nil @aliases.assignment_for(read, nil)
      end

      def test_returns_nil_for_other_node_types
        call = Prism.parse("foo").value.statements.body.first

        assert_nil @aliases.assignment_for(call, nil)
      end

      def test_returns_nil_with_unexpected_nesting_nodes
        read = last_statement("def tick(args)\n  kb = args.inputs\n  kb\nend")
        context = Object.new
        context.instance_variable_set(:@nesting_nodes, "nope")

        assert_nil @aliases.assignment_for(read, context)
      end

      def test_nearest_preceding_assignment_wins
        assignment = assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            kb = args.outputs
            k‸b
          end
        RUBY

        assert_equal "kb = args.outputs", assignment.slice
      end

      def test_assignment_inside_a_conditional_counts
        assignment = assignment_at(<<~RUBY)
          def tick(args)
            if args.state.foo
              kb = args.inputs
            end
            k‸b
          end
        RUBY

        assert_equal "kb = args.inputs", assignment.slice
      end

      def test_assignment_after_the_read_is_not_used
        assert_nil assignment_at(<<~RUBY)
          def tick(args)
            k‸b
            kb = args.inputs
          end
        RUBY
      end

      def test_chained_aliases_return_the_nearest_write
        assignment = assignment_at(<<~RUBY)
          def tick(args)
            i = args.inputs
            kb = i.keyboard
            k‸b
          end
        RUBY

        assert_equal "kb = i.keyboard", assignment.slice
      end

      def test_or_write_is_an_assignment
        assignment = assignment_at(<<~RUBY)
          def tick(args)
            kb ||= args.inputs
            k‸b
          end
        RUBY

        assert_instance_of Prism::LocalVariableOrWriteNode, assignment
      end

      def test_operator_write_is_an_assignment
        assignment = assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            kb += 1
            k‸b
          end
        RUBY

        assert_instance_of Prism::LocalVariableOperatorWriteNode, assignment
      end

      def test_multiple_assignment_target_is_an_assignment
        assignment = assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            kb, other = 1, 2
            k‸b
          end
        RUBY

        assert_instance_of Prism::LocalVariableTargetNode, assignment
      end

      def test_block_sees_enclosing_locals
        assignment = assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            [1].each { k‸b }
          end
        RUBY

        assert_equal "kb = args.inputs", assignment.slice
      end

      def test_block_parameter_shadows_an_outer_alias
        assert_nil assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            [1].each { |kb| k‸b }
          end
        RUBY
      end

      def test_block_local_shadows_an_outer_alias
        assert_nil assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            [1].each { |; kb| k‸b }
          end
        RUBY
      end

      def test_nested_blocks_see_outer_aliases
        assignment = assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            [1].each do
              [2].each do
                k‸b
              end
            end
          end
        RUBY

        assert_equal "kb = args.inputs", assignment.slice
      end

      def test_numbered_parameters_do_not_break_outer_alias_lookup
        assignment = assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            [1].each { _1; k‸b }
          end
        RUBY

        assert_equal "kb = args.inputs", assignment.slice
      end

      def test_numbered_parameters_shadow_their_names
        assert_nil assignment_at(<<~RUBY)
          def tick(args)
            [1].each { _‸1.control }
          end
        RUBY
      end

      def test_it_parameter_does_not_break_outer_alias_lookup
        assignment = assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            [1].each { it; k‸b }
          end
        RUBY

        assert_equal "kb = args.inputs", assignment.slice
      end

      def test_destructured_block_parameters_shadow_their_names
        assert_nil assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            [[1]].each { |(kb)| k‸b.control }
          end
        RUBY
      end

      def test_nested_destructured_block_parameters_shadow_their_names
        assert_nil assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            [[1]].each { |a, (b, kb)| k‸b.control }
          end
        RUBY
      end

      def test_splatted_destructured_block_parameters_shadow_their_names
        assert_nil assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            [[1]].each { |(a, *kb)| k‸b.control }
          end
        RUBY
      end

      def test_forwarding_and_keyword_rest_parameters_do_not_raise
        assignment = assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            [1].each { |...| k‸b }
          end
        RUBY

        assert_equal "kb = args.inputs", assignment.slice
      end

      def test_writes_inside_a_block_do_not_leak_past_it
        assignment = assignment_at(<<~RUBY)
          def tick(args)
            kb = args.inputs
            [1].each { kb = args.outputs }
            k‸b
          end
        RUBY

        assert_equal "kb = args.inputs", assignment.slice
      end

      def test_locals_do_not_cross_a_class_body_into_a_method
        assignment = assignment_at(<<~RUBY)
          class Game
            kb = args.inputs

            def tick
              kb = args.outputs
              k‸b
            end
          end
        RUBY

        assert_equal "kb = args.outputs", assignment.slice
      end

      def test_top_level_assignment_is_visible
        assignment = assignment_at(<<~RUBY)
          kb = args.inputs
          k‸b
        RUBY

        assert_equal "kb = args.inputs", assignment.slice
      end

      private

      def assignment_at(source, context: nil)
        context ||= locate_context(source, adjust: 0, node_types: [Prism::LocalVariableReadNode])
        refute_nil context.node, "cursor did not locate a local variable read"
        @aliases.assignment_for(context.node, context)
      end

      def last_statement(source)
        Prism.parse(source).value.statements.body.first.body.body.last
      end
    end
  end
end
