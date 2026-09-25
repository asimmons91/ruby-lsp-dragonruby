# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestResolver < Minitest::Test
      include RegistryTestHelper
      include NodeContextHelper

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

      def test_macro_accessor_roots_resolve_bare_calls
        resolution = resolve_indexed(<<~RUBY)
          class Game
            attr_gtk
            def tick
              inputs.keyboa‸rd
            end
          end
        RUBY

        assert_equal "GTK::Keyboard", resolution.type.name
      end

      def test_macro_accessor_roots_resolve_self_calls
        resolution = resolve_indexed(<<~RUBY)
          class Game
            attr_gtk
            def tick
              self.inputs.keyboa‸rd
            end
          end
        RUBY

        assert_equal "GTK::Keyboard", resolution.type.name
      end

      def test_macro_accessor_roots_work_for_subclasses
        resolution = resolve_indexed(<<~RUBY)
          class Base
            attr_gtk
          end
          class Child < Base
            def tick
              stat‸e
            end
          end
        RUBY

        assert_equal "GTK::State", resolution.type.name
      end

      def test_shared_accessor_names_use_the_applied_macro
        registry = load_registry(valid_files.merge("macros.yml" => SHARED_MACROS))
        index = RubyIndexer::Index.new
        IndexingEnhancement.registry = registry
        index.index_single(URI("file:///test.rb"), "class Game\n  attr_other\n  def tick\n    args\n  end\nend\n")

        context = locate_context("class Game\n  attr_other\n  def tick\n    ar‸gs\n  end\nend\n", adjust: 0)
        resolution = Resolver.new(registry, index: index).resolve(context.node, context)

        assert_equal "GTK::Inputs", resolution.type.name
      ensure
        IndexingEnhancement.registry = nil
      end

      def test_macro_accessor_roots_require_the_macro
        resolution = resolve_indexed(<<~RUBY)
          class Game
            def tick
              inputs.keyboa‸rd
            end
          end
        RUBY

        assert_predicate resolution, :unknown?
      end

      private

      def resolve_indexed(source)
        registry = load_registry(valid_files)
        index = RubyIndexer::Index.new
        IndexingEnhancement.registry = registry
        index.index_single(URI("file:///test.rb"), source.delete(NodeContextHelper::CURSOR))

        context = locate_context(source, adjust: 0)
        Resolver.new(registry, index: index).resolve(context.node, context)
      ensure
        IndexingEnhancement.registry = nil
      end

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
