# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestResolver < Minitest::Test
      include RegistryTestHelper

      TYPES = <<~YAML
        types:
          - name: GTK::Args
            members:
              - {name: inputs, kind: attribute, returns: GTK::Inputs, doc: Inputs}
              - {name: outputs, kind: attribute, returns: GTK::Outputs, doc: Outputs}
              - {name: mystery, kind: method, returns: Unknown, doc: Mystery}
              - {name: score, kind: method, returns: [Integer, Float], doc: Score}
          - name: GTK::Inputs
            parent: GTK::Base
            members:
              - {name: keyboard, kind: attribute, returns: GTK::Keyboard, doc: Keyboard}
          - name: GTK::Base
            members:
              - {name: base, kind: attribute, returns: Boolean, doc: Base}
          - name: GTK::Keyboard
            members:
              - {name: control, kind: attribute, returns: Boolean, doc: Ctrl, aliases: [ctrl]}
          - name: GTK::Outputs
            members:
              - {name: sprites, kind: attribute, returns: GTK::Outputs::Sprites, doc: Sprites}
              - name: "[]"
                kind: method
                returns: GTK::Outputs::RenderTarget
                doc: Render target
                params: [{name: name, kind: required, type: Symbol}]
          - name: GTK::Outputs::Collection
            members:
              - {name: length, kind: attribute, returns: Integer, doc: Length}
          - name: GTK::Outputs::Sprites
            parent: GTK::Outputs::Collection
            members:
              - {name: pushed, kind: attribute, returns: Boolean, doc: Pushed}
          - name: GTK::Outputs::RenderTarget
            parent: GTK::Outputs::Collection
            members:
              - {name: w, kind: attribute, returns: Numeric, doc: Width}
          - name: GTK::Runtime
            members:
              - {name: args, kind: attribute, returns: GTK::Args, doc: Args}
          - name: Geometry
            members:
              - {name: angle_to, kind: method, returns: Float, doc: Angle}
      YAML

      class SelfRoot < Roots::Strategy
        def resolve(node, _context)
          type_for("GTK::Args") if node.is_a?(Prism::SelfNode)
        end
      end

      def setup
        @registry = load_registry({"metadata.yml" => METADATA, "types.yml" => TYPES})
        @resolver = Resolver.new(@registry)
      end

      def test_parameter_root
        resolution = @resolver.resolve(argument_to("def tick(args)\n  args.inputs\nend"))

        assert_equal "GTK::Args", resolution.type.name
        assert_predicate resolution, :confident?
      end

      def test_global_roots
        assert_equal "GTK::Runtime", @resolver.resolve(expression("$gtk")).type.name
        assert_equal "GTK::Args", @resolver.resolve(expression("$args")).type.name
      end

      def test_constant_roots
        assert_equal "Geometry", @resolver.resolve(expression("Geometry")).type.name
        assert_equal "GTK::Args", @resolver.resolve(expression("GTK::Args")).type.name
        assert_predicate @resolver.resolve(expression("Nope")), :unknown?
      end

      def test_chain_resolution_through_members
        resolution = @resolver.resolve(expression("def tick(args)\n  args.inputs.keyboard\nend"))

        assert_equal "GTK::Keyboard", resolution.type.name
      end

      def test_parent_members_and_core_returns
        resolution = @resolver.resolve(body_expression("def tick(args)\n  args.inputs.base\nend"))

        refute_predicate resolution, :resolved_type?
        assert_predicate resolution, :confident?
        assert_equal "Boolean", resolution.core_type
      end

      def test_alias_member_lookup
        resolution = @resolver.resolve(body_expression("def tick(args)\n  args.inputs.keyboard.ctrl\nend"))

        assert_equal "Boolean", resolution.core_type
      end

      def test_missing_member_stops_resolution
        assert_predicate @resolver.resolve(expression("def tick(args)\n  args.nope\nend")), :unknown?
        assert_predicate @resolver.resolve(expression("def tick(args)\n  args.inputs.nope.keyboard\nend")), :unknown?
      end

      def test_unknown_hop_stops_resolution
        assert_predicate @resolver.resolve(expression("def tick(args)\n  args.mystery.foo\nend")), :unknown?
      end

      def test_union_returns_stop_resolution
        assert_predicate @resolver.resolve(expression("def tick(args)\n  args.score\nend")), :unknown?
      end

      def test_safe_navigation
        resolution = @resolver.resolve(expression("def tick(args)\n  args&.inputs&.keyboard\nend"))

        assert_equal "GTK::Keyboard", resolution.type.name
      end

      def test_parenthesized_receivers
        resolution = @resolver.resolve(expression("def tick(args)\n  (args.inputs).keyboard\nend"))

        assert_equal "GTK::Keyboard", resolution.type.name
      end

      def test_index_calls_resolve_to_their_return_type
        resolution = @resolver.resolve(body_expression("def tick(args)\n  args.outputs[:rt]\nend"))

        assert_equal "GTK::Outputs::RenderTarget", resolution.type.name
      end

      def test_index_call_chains_continue
        resolution = @resolver.resolve(body_expression("def tick(args)\n  args.outputs[:rt].w\nend"))

        assert_equal "Numeric", resolution.core_type
      end

      def test_unrecognized_root_stops_resolution
        assert_predicate @resolver.resolve(expression("foo.bar")), :unknown?
      end

      def test_root_strategies_are_extensible
        roots = Roots.new(@registry, strategies: [SelfRoot, Roots::Parameter, Roots::Global, Roots::RegistryConstant])
        resolver = Resolver.new(@registry, roots: roots)
        resolution = resolver.resolve(expression("self"))

        assert_equal "GTK::Args", resolution.type.name
      end

      private

      def expression(source)
        statements = Prism.parse(source).value.statements.body
        first = statements.first
        first.is_a?(Prism::DefNode) ? first.body.body.last : statements.last
      end

      def argument_to(source)
        expression(source).receiver
      end

      def body_expression(source)
        Prism.parse(source).value.statements.body.first.body.body.last
      end
    end
  end
end
