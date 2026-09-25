# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestWarnings < Minitest::Test
      include RegistryTestHelper

      TYPES = <<~YAML
        types:
          - name: GTK::Args
            members:
              - {name: inputs, kind: attribute, returns: GTK::Inputs, doc: Inputs}
              - {name: outputs, kind: attribute, returns: GTK::Outputs, doc: Outputs}
              - {name: state, kind: attribute, returns: GTK::State, doc: State}
              - {name: partial, kind: attribute, returns: GTK::Partial, doc: Partial}
              - {name: audio, kind: attribute, returns: GTK::HashLike, doc: Audio}
          - name: GTK::Inputs
            members:
              - {name: keyboard, kind: attribute, returns: GTK::Keyboard, doc: Keyboard}
          - name: GTK::Keyboard
            members:
              - {name: key_down, kind: attribute, returns: GTK::Keys, doc: Key down}
          - name: GTK::Keys
            members:
              - {name: space, kind: attribute, returns: Boolean, doc: Space}
          - name: GTK::State
            open: true
            members: []
          - name: GTK::Partial
            incomplete: true
            members: []
          - name: GTK::Outputs
            members:
              - {name: sprites, kind: attribute, returns: GTK::Outputs::Sprites, doc: Sprites}
          - name: GTK::Outputs::Collection
            core_backing: Array
            members:
              - {name: "<<", kind: method, returns: GTK::Outputs::Collection, doc: Push}
          - name: GTK::Outputs::Sprites
            parent: GTK::Outputs::Collection
            accepts_primitive: sprite
            members: []
          - name: GTK::HashLike
            core_backing: Hash
            members: []
      YAML

      SCHEMAS = <<~YAML
        schemas:
          - name: sprite
            primitive_marker: sprite
            keys:
              - {name: x, type: Numeric, doc: X}
              - {name: path, type: [String, Symbol], doc: Path}
      YAML

      def registry
        @registry ||= load_registry({
          "metadata.yml" => METADATA,
          "types.yml" => TYPES,
          "schemas.yml" => SCHEMAS
        })
      end

      def analyze(source, settings: nil, index: nil, state: nil)
        program = Prism.parse(source).value
        Warnings::Analyzer.new(registry, index: index, state: state, settings: settings).diagnostics(program)
      end

      def messages(diagnostics)
        diagnostics.map(&:message)
      end

      def test_undefined_member_warns_with_suggestion
        diagnostics = analyze("def tick(args)\n  args.inputs.keybaord\nend\n")

        assert_equal 1, diagnostics.size
        diagnostic = diagnostics.first
        assert_equal "`keybaord` is not a known member of `GTK::Inputs` in DragonRuby 5.0. " \
          "Did you mean `keyboard`?", diagnostic.message
        assert_equal RubyLsp::Constant::DiagnosticSeverity::WARNING, diagnostic.severity
        assert_equal "dragonruby", diagnostic.source
        assert_equal 1, diagnostic.range.start.line
      end

      def test_open_type_never_warns
        assert_empty analyze("def tick(args)\n  args.state.anything\nend\n")
      end

      def test_incomplete_type_never_warns
        assert_empty analyze("def tick(args)\n  args.partial.mystery\nend\n")
      end

      def test_unknown_root_never_warns
        assert_empty analyze("def tick(args)\n  foo.inputs.keybaord\nend\n")
      end

      def test_known_members_never_warn
        assert_empty analyze("def tick(args)\n  args.inputs.keyboard.key_down.space\nend\n")
      end

      def test_standard_object_methods_never_warn
        assert_empty analyze(<<~RUBY)
          def tick(args)
            args.inputs.inspect
            args.inputs.send(:foo)
            args.inputs.frozen?
          end
        RUBY
      end

      def test_core_backed_collection_methods_never_warn
        assert_empty analyze(<<~RUBY)
          def tick(args)
            args.outputs.sprites.size
            args.outputs.sprites.map { |sprite| sprite }
            args.audio.length
            args.audio.keys
          end
        RUBY
      end

      def test_unknown_members_on_core_backed_types_still_warn
        diagnostics = analyze("def tick(args)\n  args.audio.mystery\nend\n")

        assert_equal ["`mystery` is not a known member of `GTK::HashLike` in DragonRuby 5.0."],
          messages(diagnostics)
      end

      def test_allowlist_suppresses_warnings
        settings = Settings.new("warnings" => {"allowlist" => ["keybaord"]})

        assert_empty analyze("def tick(args)\n  args.inputs.keybaord\nend\n", settings: settings)
      end

      def test_disabled_settings_produce_no_diagnostics
        settings = Settings.new("warnings" => {"enabled" => false})

        assert_empty analyze("def tick(args)\n  args.inputs.keybaord\nend\n", settings: settings)
      end

      def test_disabled_settings_suppress_optional_warnings
        settings = Settings.new(
          "warnings" => {"enabled" => false, "primitiveKeys" => true, "unassignedStateReads" => true}
        )
        source = "def tick(args)\n  args.outputs.sprites << { x: 0, bogus: 1 }\n  args.state.player\nend\n"
        state = FakeState.new(registry)

        assert_empty analyze(source, settings: settings, state: state)
      end

      def test_index_definition_suppresses_warning
        index = RubyIndexer::Index.new
        index.index_single(URI("file:///reopen.rb"), "class GTK::Inputs\n  def my_helper; end\nend")

        assert_empty analyze("def tick(args)\n  args.inputs.my_helper\nend\n", index: index)

        assert_equal 1, analyze("def tick(args)\n  args.inputs.my_helper\nend\n").size
      end

      def test_alias_chain_warns
        diagnostics = analyze("def tick(args)\n  s = args.outputs\n  s.spritess\nend\n")

        assert_equal ["`spritess` is not a known member of `GTK::Outputs` in DragonRuby 5.0. " \
          "Did you mean `sprites`?"], messages(diagnostics)
      end

      def test_attribute_writes_do_not_warn
        assert_empty analyze("def tick(args)\n  args.inputs.keyboard.unknown = 1\nend\n")
      end

      def test_incomplete_code_does_not_raise
        assert_empty analyze("def tick(args)\n  args.inputs.\nend\n")
        assert_empty analyze("def tick(args)\n  args.outputs.sprites << { x: 0,\nend\n")

        half_typed = analyze("def tick(args)\n  args.inputs.keyb\nend\n")
        assert_equal ["`keyb` is not a known member of `GTK::Inputs` in DragonRuby 5.0."], messages(half_typed)
      end

      def test_primitive_keys_are_off_by_default
        assert_empty analyze(<<~RUBY)
          def tick(args)
            args.outputs.sprites << { x: 0, bogus: 1 }
          end
        RUBY
      end

      def test_primitive_keys_warn_when_enabled
        settings = Settings.new("warnings" => {"primitiveKeys" => true})
        diagnostics = analyze(<<~RUBY, settings: settings)
          def tick(args)
            args.outputs.sprites << { x: 0, bogus: 1 }
          end
        RUBY

        assert_equal ["`bogus` is not a known key of the sprite primitive in DragonRuby 5.0."],
          messages(diagnostics)
        assert_equal RubyLsp::Constant::DiagnosticSeverity::HINT, diagnostics.first.severity
      end

      def test_primitive_keys_skip_unclosed_hashes
        settings = Settings.new("warnings" => {"primitiveKeys" => true})

        assert_empty analyze(<<~RUBY, settings: settings)
          def tick(args)
            args.outputs.sprites << { x: 0, bogus: 1,
          end
        RUBY
      end

      def test_primitive_keys_accept_marker_and_known_keys
        settings = Settings.new("warnings" => {"primitiveKeys" => true})

        assert_empty analyze(<<~RUBY, settings: settings)
          def tick(args)
            args.outputs.sprites << { primitive_marker: :sprite, path: "a.png" }
          end
        RUBY
      end

      def test_allowlist_suppresses_primitive_key_warnings
        settings = Settings.new("warnings" => {"primitiveKeys" => true, "allowlist" => ["bogus"]})

        assert_empty analyze(<<~RUBY, settings: settings)
          def tick(args)
            args.outputs.sprites << { x: 0, bogus: 1 }
          end
        RUBY
      end

      def test_unassigned_state_reads_are_off_by_default
        state = FakeState.new(registry)

        assert_empty analyze("def tick(args)\n  args.state.player\nend\n", state: state)
      end

      def test_unassigned_state_reads_warn_when_enabled
        settings = Settings.new("warnings" => {"unassignedStateReads" => true})
        state = FakeState.new(registry)
        diagnostics = analyze("def tick(args)\n  args.state.player\nend\n", settings: settings, state: state)

        assert_equal ["State path `player` is read but has no write sites in this workspace."],
          messages(diagnostics)
        assert_equal RubyLsp::Constant::DiagnosticSeverity::HINT, diagnostics.first.severity
      end

      def test_assigned_state_reads_do_not_warn
        settings = Settings.new("warnings" => {"unassignedStateReads" => true})
        state = FakeState.new(registry, paths: ["player"])

        assert_empty analyze("def tick(args)\n  args.state.player\nend\n", settings: settings, state: state)
      end

      def test_unassigned_state_reads_skip_before_scan
        settings = Settings.new("warnings" => {"unassignedStateReads" => true})
        state = FakeState.new(registry, scanned: false)

        assert_empty analyze("def tick(args)\n  args.state.player\nend\n", settings: settings, state: state)
      end

      class FakeState
        attr_reader :resolver, :store

        def initialize(registry, scanned: true, paths: [])
          @scanned = scanned
          @paths = paths.to_set
          @store = nil
          @resolver = Resolver.new(registry)
        end

        def scanned?
          @scanned
        end

        def path?(path)
          @paths.include?(path)
        end
      end
    end
  end
end
