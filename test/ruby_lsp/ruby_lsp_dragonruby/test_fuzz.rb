# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/ruby_lsp_dragonruby/addon"
require_relative "../../../benchmark/sample_workspace"

module RubyLsp
  module Dragonruby
    # REQ-M8-02: every feature, at every cursor position in the sample game,
    # must raise nothing. The sweep drives the add-on's listener callbacks
    # directly with the node context Ruby LSP would provide. The add-on's
    # entry points rescue and log errors, so the assertion is that the quiet
    # logger stays empty; anything that escapes a callback fails the test.
    class TestFuzz < Minitest::Test
      include RegistryTestHelper
      include ServerTestHelper

      FUZZ_URI = URI("file:///fuzz_sample_game.rb")

      FUZZ_TARGETS = (
        RubyLsp::Listeners::Hover::ALLOWED_TARGETS +
        [Prism::CallNode, Prism::LocalVariableReadNode]
      ).uniq.freeze

      def test_every_cursor_position_in_the_sample_game_is_error_free
        logger = quiet_logger
        addon = Addon.new(logger: logger)
        addon.activate(nil, nil)

        Benchmarks::SampleWorkspace.game_sources.each do |name, source|
          sweep(addon, name, source)
        end

        assert_empty logger.messages, logger.messages.join("\n")
      ensure
        addon&.deactivate
      end

      def test_diagnostics_never_raise_on_the_sample_game
        logger = quiet_logger
        addon = Addon.new(logger: logger)
        addon.activate(nil, nil)
        formatter = Warnings::Formatter.new(
          addon.registry,
          index: nil,
          state: addon.state_tracker,
          global_state: nil,
          logger: logger
        )

        Benchmarks::SampleWorkspace.game_sources.each_value do |source|
          formatter.run_diagnostic(FUZZ_URI, build_document(source))
        end

        assert_empty logger.messages, logger.messages.join("\n")
      ensure
        addon&.deactivate
      end

      def test_server_requests_at_sample_positions_log_no_add_on_errors
        Benchmarks::SampleWorkspace.game_sources.each do |name, source|
          with_workspace_server(source) do |server, uri|
            mark_indexing_complete(server)
            configure_addon(server, linters: ["dragonruby"], settings: {})
            addon = dragonruby_addon(server)

            cursor_positions(source).each do |line, character|
              completion_items(server, uri, line, character)
              hover_content(server, uri, line, character)
              definition_locations(server, uri, line, character)
            end
            diagnostic_items(server, uri)

            errors = addon.instance_variable_get(:@logger).messages
            assert_empty errors, "#{name}: #{errors.join("\n")}"
          end
        end
      end

      private

      def sweep(addon, name, source)
        document = build_document(source)
        addon.state_tracker.replace_source(FUZZ_URI, source)
        parents = parent_map(document.ast)

        each_offset(source) do |offset|
          context = RubyLsp::RubyDocument.locate(
            document.ast,
            offset,
            code_units_cache: document.code_units_cache,
            node_types: FUZZ_TARGETS
          )
          next unless context.node

          exercise(addon, context, parents)
        rescue => error
          flunk "#{name} raised at offset #{offset}: #{error.class}: #{error.message}"
        end
      end

      def exercise(addon, context, parents)
        node = context.node

        completion = addon.create_completion_listener(
          RubyLsp::ResponseBuilders::CollectionResponseBuilder.new,
          context,
          Prism::Dispatcher.new,
          FUZZ_URI
        )
        hover = addon.create_hover_listener(
          RubyLsp::ResponseBuilders::Hover.new,
          context,
          Prism::Dispatcher.new
        )
        definition = addon.create_definition_listener(
          RubyLsp::ResponseBuilders::CollectionResponseBuilder.new,
          FUZZ_URI,
          context,
          Prism::Dispatcher.new
        )

        if node.is_a?(Prism::CallNode)
          completion&.on_call_node_enter(node)
          hover&.on_call_node_enter(node)
          definition&.on_call_node_enter(node)
        end

        case node
        when Prism::SymbolNode then hover&.on_symbol_node_enter(node)
        when Prism::StringNode then hover&.on_string_node_enter(node)
        when Prism::GlobalVariableReadNode then hover&.on_global_variable_read_node_enter(node)
        when Prism::LocalVariableReadNode then hover&.on_local_variable_read_node_enter(node)
        when Prism::ConstantReadNode then hover&.on_constant_read_node_enter(node)
        when Prism::ConstantPathNode then hover&.on_constant_path_node_enter(node)
        end

        # Extra coverage beyond a real request: Ruby LSP's `dispatch_once` fires
        # only the located target, but enclosing calls are exercised with the
        # cursor's node context too.
        ancestor = parents[node.object_id]
        while ancestor
          if ancestor.is_a?(Prism::CallNode)
            completion&.on_call_node_enter(ancestor)
            hover&.on_call_node_enter(ancestor)
            definition&.on_call_node_enter(ancestor)
          end
          ancestor = parents[ancestor.object_id]
        end
      end

      def each_offset(source, &block)
        (0...source.length).each(&block)
      end

      def parent_map(ast)
        map = {}
        each_node(ast) do |node|
          node.compact_child_nodes.each { |child| map[child.object_id] = node }
        end
        map
      end

      def each_node(node, &block)
        return unless node

        yield node
        node.compact_child_nodes.each { |child| each_node(child, &block) }
      end

      def build_document(source)
        RubyLsp::RubyDocument.new(
          source: source,
          version: 1,
          uri: FUZZ_URI,
          global_state: RubyLsp::GlobalState.new
        )
      end

      # A few representative request positions per file: every method call and
      # every opening brace in the source.
      def cursor_positions(source)
        positions = []
        source.each_line.with_index do |line, index|
          line.to_enum(:scan, /[.{}]/).each do
            match = Regexp.last_match
            positions << [index, match.end(0)]
          end
        end
        positions.first(20)
      end
    end
  end
end
