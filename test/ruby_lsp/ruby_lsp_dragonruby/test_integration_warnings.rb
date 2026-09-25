# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestIntegrationWarnings < Minitest::Test
      include ServerTestHelper

      UNDEFINED_MEMBER = "def tick(args)\n  args.inputs.keybaord\nend\n"

      class StubLinter
        include RubyLsp::Requests::Support::Formatter

        def run_formatting(uri, document) = nil
        def run_range_formatting(uri, source, base_indentation) = nil

        def run_diagnostic(uri, document)
          [RubyLsp::Interface::Diagnostic.new(
            range: RubyLsp::Interface::Range.new(
              start: RubyLsp::Interface::Position.new(line: 0, character: 0),
              end: RubyLsp::Interface::Position.new(line: 0, character: 1)
            ),
            message: "stub diagnostic",
            severity: RubyLsp::Constant::DiagnosticSeverity::WARNING,
            source: "stub"
          )]
        end
      end

      def test_hover_warns_for_an_undefined_member
        with_cursor("def tick(args)\n  args.inputs.keyba‸ord\nend\n") do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          assert_includes content,
            "`keybaord` is not a known member of `GTK::Inputs` in DragonRuby 7.18. Did you mean `keyboard`?"
        end
      end

      def test_hover_never_warns_on_open_types
        with_cursor("def tick(args)\n  args.state.any‸thing\nend\n") do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          refute_match(/not a known member/, content.to_s)
        end
      end

      def test_hover_never_warns_for_unknown_roots
        with_cursor("def tick(args)\n  foo.inputs.keyb‸aord\nend\n") do |server, uri, line, character|
          content = hover_content(server, uri, line, character)

          refute_match(/not a known member/, content.to_s)
        end
      end

      def test_hover_warns_through_attr_gtk_accessors
        source = "class Game\n  attr_gtk\n\n  def tick\n    outputs.sprit‸ess\n  end\nend\n"
        with_cursor(source) do |server, uri, line, character|
          reindex(server, uri, source)
          content = hover_content(server, uri, line, character)

          assert_includes content, "not a known member of `GTK::Outputs`"
          assert_includes content, "Did you mean `sprites`?"
        end
      end

      def test_hover_never_warns_for_core_backed_collection_methods
        with_cursor("def tick(args)\n  args.audio.len‸gth\nend\n") do |server, uri, line, character|
          refute_match(/not a known member/, hover_content(server, uri, line, character).to_s)
        end

        with_cursor("def tick(args)\n  args.outputs.sprites.si‸ze\nend\n") do |server, uri, line, character|
          refute_match(/not a known member/, hover_content(server, uri, line, character).to_s)
        end
      end

      def test_warnings_can_be_disabled
        settings = {"warnings" => {"enabled" => false}}
        with_cursor("def tick(args)\n  args.inputs.keyba‸ord\nend\n") do |server, uri, line, character|
          configure_addon(server, settings: settings)
          content = hover_content(server, uri, line, character)

          refute_match(/not a known member/, content.to_s)
        end
      end

      def test_diagnostics_require_the_linter_opt_in
        with_workspace_server(UNDEFINED_MEMBER) do |server, uri|
          assert_empty dragonruby_items(server, uri)
        end
      end

      def test_diagnostics_report_undefined_members
        with_workspace_server(UNDEFINED_MEMBER) do |server, uri|
          configure_addon(server, linters: [Settings::LINTER_ID])
          items = dragonruby_items(server, uri)

          assert_equal 1, items.size
          assert_equal RubyLsp::Constant::DiagnosticSeverity::WARNING, items.first.severity
          assert_includes items.first.message, "Did you mean `keyboard`?"
        end
      end

      def test_diagnostics_coexist_with_another_linter
        with_workspace_server(UNDEFINED_MEMBER) do |server, uri|
          server.global_state.register_formatter("stub_linter", StubLinter.new)
          configure_addon(server, linters: ["stub_linter", Settings::LINTER_ID])
          items = diagnostic_items(server, uri)

          assert(items.any? { |item| item.source == "stub" })
          assert(items.any? { |item| item.source == "dragonruby" })
        end
      end

      def test_diagnostics_can_be_disabled
        with_workspace_server(UNDEFINED_MEMBER) do |server, uri|
          configure_addon(server, settings: {"warnings" => {"enabled" => false}}, linters: [Settings::LINTER_ID])

          assert_empty dragonruby_items(server, uri)
        end
      end

      def test_reopened_dragonruby_classes_suppress_warnings
        source = "class GTK::Outputs\n  def my_helper; end\nend\n\n" \
          "def tick(args)\n  args.outputs.my_helper\nend\n"
        with_workspace_server(source) do |server, uri|
          configure_addon(server, linters: [Settings::LINTER_ID])

          assert_empty dragonruby_items(server, uri)
        end
      end

      def test_primitive_key_diagnostics_are_off_by_default
        source = "def tick(args)\n  args.outputs.sprites << { x: 0, bogus: 1 }\nend\n"
        with_workspace_server(source) do |server, uri|
          configure_addon(server, linters: [Settings::LINTER_ID])

          assert_empty dragonruby_items(server, uri)
        end
      end

      def test_primitive_key_diagnostics_warn_when_enabled
        source = "def tick(args)\n  args.outputs.sprites << { x: 0, bogus: 1 }\nend\n"
        with_workspace_server(source) do |server, uri|
          configure_addon(
            server,
            settings: {"warnings" => {"primitiveKeys" => true}},
            linters: [Settings::LINTER_ID]
          )
          items = dragonruby_items(server, uri)

          assert_equal 1, items.size
          assert_equal RubyLsp::Constant::DiagnosticSeverity::HINT, items.first.severity
          assert_includes items.first.message, "`bogus`"
        end
      end

      def test_unassigned_state_read_diagnostics_warn_when_enabled
        source = "def tick(args)\n  args.state.player\nend\n"
        with_workspace_server(source) do |server, uri|
          mark_state_scanned(server)
          configure_addon(
            server,
            settings: {"warnings" => {"unassignedStateReads" => true}},
            linters: [Settings::LINTER_ID]
          )
          items = dragonruby_items(server, uri)

          assert_equal 1, items.size
          assert_equal RubyLsp::Constant::DiagnosticSeverity::HINT, items.first.severity
          assert_includes items.first.message, "`player`"
        end
      end

      def test_unassigned_state_read_diagnostics_respect_other_files
        source = "def tick(args)\n  args.state.player\nend\n"
        writer = "def write(args)\n  args.state.player ||= {}\nend\n"
        with_workspace_server(source) do |server, uri|
          mark_state_scanned(server)
          reindex_state(server, URI::Generic.from_path(path: File.join(Dir.pwd, "writer.rb")), writer)
          configure_addon(
            server,
            settings: {"warnings" => {"unassignedStateReads" => true}},
            linters: [Settings::LINTER_ID]
          )

          assert_empty dragonruby_items(server, uri)
        end
      end

      def test_incomplete_code_produces_no_diagnostics
        with_workspace_server("def tick(args)\n  args.inputs.\nend\n") do |server, uri|
          configure_addon(server, linters: [Settings::LINTER_ID])

          assert_empty dragonruby_items(server, uri)
        end

        with_workspace_server("def tick(args)\n  args.outputs.sprites << { x: 0, bogus: 1,\nend\n") do |server, uri|
          configure_addon(
            server,
            settings: {"warnings" => {"primitiveKeys" => true}},
            linters: [Settings::LINTER_ID]
          )

          assert_empty dragonruby_items(server, uri)
        end
      end
    end
  end
end
