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
              - {name: state, kind: attribute, returns: GTK::State, doc: State}
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
          - name: GTK::State
            open: true
            members:
              - {name: new_entity, kind: method, returns: GTK::Entity, doc: Entity}
          - name: GTK::Entity
            open: true
            members:
              - {name: x, kind: attribute, returns: Numeric, doc: X}
              - name: inside_rect?
                kind: method
                returns: Boolean
                doc: Inside
                params: [{name: rect, kind: required, type: Object}]
          - name: Numeric
            core_extension: true
            members:
              - {name: seconds, kind: method, returns: Integer, doc: Seconds}
              - {name: frame_index, kind: method, returns: Integer, scope: both, doc: Frame}
          - name: Integer
            core_extension: true
            parent: Numeric
            members: []
          - name: Hash
            core_extension: true
            members:
              - name: intersect_rect?
                kind: method
                returns: Boolean
                doc: Intersect
                params: [{name: other, kind: required, type: Object}]
          - name: Kernel
            core_extension: true
            members:
              - {name: tick_count, kind: attribute, returns: Integer, scope: both, doc: Tick}
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

      def test_local_alias_resolves_its_assigned_type
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            kb = args.inputs.keyboard
            kb.contro‸l
          end
        RUBY

        assert_equal "Boolean", resolution.core_type
      end

      def test_chained_local_aliases_resolve
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            i = args.inputs
            kb = i.keyboard
            kb.contro‸l
          end
        RUBY

        assert_equal "Boolean", resolution.core_type
      end

      def test_reassignment_replaces_the_earlier_type
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            source = args.inputs
            source = args.outputs
            source.sprit‸es
          end
        RUBY

        assert_equal "GTK::Outputs::Sprites", resolution.type.name
      end

      def test_reassignment_to_an_unresolvable_expression_stops_resolution
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            kb = args.inputs.keyboard
            kb = nil
            kb.contro‸l
          end
        RUBY

        assert_predicate resolution, :unknown?
      end

      def test_reassigning_a_parameter_replaces_the_root
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            args = nil
            args.inp‸uts
          end
        RUBY

        assert_predicate resolution, :unknown?
      end

      def test_assignments_inside_conditionals_count
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            if args.state.foo
              kb = args.inputs.keyboard
            end
            kb.contro‸l
          end
        RUBY

        assert_equal "Boolean", resolution.core_type
      end

      def test_block_parameters_shadow_outer_aliases
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            kb = args.inputs.keyboard
            [1].each { |kb| kb.contro‸l }
          end
        RUBY

        assert_predicate resolution, :unknown?
      end

      def test_destructured_block_parameters_shadow_outer_aliases
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            kb = args.inputs.keyboard
            [[1]].each { |(kb)| kb.contro‸l }
          end
        RUBY

        assert_predicate resolution, :unknown?
      end

      def test_block_locals_do_not_leak_out
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            [1].each { kb = args.inputs.keyboard }
            kb.contro‸l
          end
        RUBY

        assert_predicate resolution, :unknown?
      end

      def test_parenthesized_alias_receivers_resolve
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            kb = args.inputs.keyboard
            (kb).contro‸l
          end
        RUBY

        assert_equal "Boolean", resolution.core_type
      end

      def test_safe_navigation_through_an_alias_resolves
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            kb = args.inputs.keyboard
            kb&.contro‸l
          end
        RUBY

        assert_equal "Boolean", resolution.core_type
      end

      def test_self_referential_alias_is_unknown
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            kb = kb
            kb.contro‸l
          end
        RUBY

        assert_predicate resolution, :unknown?
      end

      def test_operator_writes_stop_resolution
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            kb = args.inputs.keyboard
            kb += 1
            kb.contro‸l
          end
        RUBY

        assert_predicate resolution, :unknown?
      end

      def test_alias_resolution_without_a_context_is_unknown
        read = Prism.parse("def tick(args)\n  kb = args.inputs\n  kb\nend").value.statements.body.first.body.body.last

        assert_predicate @resolver.resolve(read, nil), :unknown?
      end

      def test_state_root_resolves_to_the_state_type
        resolution = resolve_at_cursor("def tick(args)\n  args.sta‸te\nend")

        assert_equal "GTK::State", resolution.type.name
      end

      def test_unknown_state_members_resolve_to_a_state_path
        resolution = resolve_at_cursor("def tick(args)\n  args.state.play‸er\nend")

        assert_predicate resolution, :state_path?
        assert_equal "player", resolution.state_path
        assert_predicate resolution, :confident?
        refute_predicate resolution, :resolved_type?
      end

      def test_nested_state_paths_extend
        resolution = resolve_at_cursor("def tick(args)\n  args.state.player.hi‸t\nend")

        assert_equal "player.hit", resolution.state_path
      end

      def test_state_alias_resolves_to_a_state_path
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            s = args.state
            s.play‸er
          end
        RUBY

        assert_equal "player", resolution.state_path
      end

      def test_state_sub_path_alias_extends
        resolution = resolve_at_cursor(<<~RUBY)
          def tick(args)
            p = args.state.player
            p.hi‸t
          end
        RUBY

        assert_equal "player.hit", resolution.state_path
      end

      def test_known_state_paths_win_over_curated_entity_members
        store = StateStore.new
        store.replace("file:///test.rb", [
          StateStore::Record.new(
            path: "player.x",
            parent: "player",
            site: StateStore::WriteSite.new(
              uri: "file:///test.rb", line: 0, character: 0, end_line: 0, end_character: 1,
              kind: :initialization, type_name: "Integer"
            )
          )
        ])
        resolver = Resolver.new(@registry, state_store: store)

        result = resolve_with(resolver, "def tick(args)\n  args.state.player.‸x\nend")

        assert_equal "player.x", result.state_path
      end

      def test_argument_calls_on_state_paths_stop_resolution
        resolution = resolve_at_cursor("def tick(args)\n  args.state.player.no‸pe(1)\nend")

        assert_predicate resolution, :unknown?
      end

      def test_state_calls_with_arguments_stop_resolution
        resolution = resolve_at_cursor("def tick(args)\n  args.state.play‸er(1)\nend")

        assert_predicate resolution, :unknown?
      end

      def test_entity_members_on_state_paths_resolve_through_the_registry
        resolution = resolve_at_cursor("def tick(args)\n  args.state.player.inside_re‸ct?(:r)\nend")

        assert_equal "Boolean", resolution.core_type
      end

      def test_curated_state_members_win_over_paths
        resolution = resolve_at_cursor("def tick(args)\n  args.state.new_ent‸ity\nend")

        assert_equal "GTK::Entity", resolution.type.name
      end

      def test_literal_receivers_resolve_to_their_core_types
        assert_equal "Integer", @resolver.resolve(expression("5")).core_type
        assert_equal "Float", @resolver.resolve(expression("1.5")).core_type
        assert_equal "Hash", @resolver.resolve(expression("{}")).core_type
        assert_equal "Array", @resolver.resolve(expression("[]")).core_type
        assert_equal "String", @resolver.resolve(expression("\"\"")).core_type
        assert_equal "String", @resolver.resolve(expression("\"a\#{1}\"")).core_type
        assert_equal "Symbol", @resolver.resolve(expression(":sym")).core_type
      end

      def test_core_extension_members_resolve_through_literal_receivers
        resolution = resolve_at_cursor("def tick(args)\n  5.sec‸onds\nend")

        assert_equal "Integer", resolution.core_type
      end

      def test_core_extension_members_resolve_through_registry_returns
        resolution = resolve_at_cursor("def tick(args)\n  args.outputs.sprites.length.sec‸onds\nend")

        assert_equal "Integer", resolution.core_type
      end

      def test_core_extension_members_resolve_for_state_paths_with_inferred_types
        store = StateStore.new
        store.replace("file:///test.rb", [
          StateStore::Record.new(
            path: "player",
            parent: "",
            site: StateStore::WriteSite.new(
              uri: "file:///test.rb", line: 0, character: 0, end_line: 0, end_character: 1,
              kind: :initialization, type_name: "Hash"
            )
          )
        ])
        resolver = Resolver.new(@registry, state_store: store)

        result = resolve_with(resolver, "def tick(args)\n  args.state.player.intersect_re‸ct?(:r)\nend")

        assert_equal "Boolean", result.core_type
      end

      def test_kernel_members_resolve_as_receiverless_calls
        resolution = resolve_at_cursor("def tick(args)\n  tick_co‸unt\nend")

        assert_equal "Integer", resolution.core_type
      end

      def test_core_extension_constants_resolve_their_members
        resolution = resolve_at_cursor("def tick(args)\n  Numeric.frame_‸index\nend")

        assert_equal "Integer", resolution.core_type
      end

      private

      def resolve_with(resolver, source)
        context = locate_context(source, adjust: 0, node_types: [Prism::CallNode])
        resolver.resolve(context.node, context)
      end

      def resolve_at_cursor(source)
        context = locate_context(source, adjust: 0, node_types: [Prism::CallNode])
        @resolver.resolve(context.node, context)
      end

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
