# frozen_string_literal: true

# Performance benchmark suite for REQ-PERF-02 and REQ-PERF-03.
#
# Run with `bundle exec ruby benchmark/run.rb` (or `bundle exec rake benchmark`).
# Exits non-zero when a budget is exceeded so CI enforces the targets.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "stringio"
require "uri"
require "ruby_lsp/internal"

require "ruby_lsp_dragonruby/logger"
require "ruby_lsp_dragonruby/registry"
require "ruby_lsp_dragonruby/settings"
require "ruby_lsp_dragonruby/state_tracker"
require "ruby_lsp_dragonruby/state_collector"
require "ruby_lsp_dragonruby/state_store"
require "ruby_lsp_dragonruby/listeners/completion"
require "ruby_lsp_dragonruby/listeners/definition"
require "ruby_lsp_dragonruby/listeners/hover"
require "ruby_lsp/ruby_lsp_dragonruby/addon"

require_relative "sample_workspace"

module RubyLsp
  module Dragonruby
    module Benchmarks
      # REQ-PERF-02: under 10 ms p95 for the add-on's share of a completion or
      # hover request on a typical game file.
      PERF_02_BUDGET = 0.010
      # REQ-PERF-03: the initial workspace scan for ~50 files / ~10k lines
      # finishes in under a second.
      PERF_03_BUDGET = 1.0

      LOCATE_TARGETS = (RubyLsp::Listeners::Hover::ALLOWED_TARGETS + [
        Prism::CallNode,
        Prism::LocalVariableReadNode
      ]).uniq.freeze

      # Mirrors the add-on work of a request: Ruby LSP creates the add-on
      # listeners and then calls `dispatch_once` on the located target node, so
      # one callback per listener fires. Invoking that callback directly
      # isolates the add-on's share from Prism's dispatch overhead.
      class Requests
        SAMPLE_LIMIT = 250

        attr_reader :positions

        def initialize
          @logger = Logger.new(StringIO.new)
          @addon = Addon.new(logger: @logger)
          @addon.activate(nil, nil)
          @registry = @addon.registry
          @uri = URI("file:///benchmark_sample_game.rb")
          @source = File.read(File.join(SampleWorkspace.game_dir, "main.rb"))
          @document = build_document(@source)
          @addon.state_tracker.replace_source(@uri, @source)
          @positions = sample_positions
          raise "benchmark setup failed: #{@logger.messages.join("\n")}" if @logger.messages.any?
        end

        def deactivate
          @addon.deactivate
        end

        def error_messages
          @logger.messages
        end

        def completion_timings
          timed do |context|
            builder = RubyLsp::ResponseBuilders::CollectionResponseBuilder.new
            listener = @addon.create_completion_listener(builder, context, Prism::Dispatcher.new, @uri)
            listener&.on_call_node_enter(context.node) if context.node.is_a?(Prism::CallNode)
          end
        end

        def hover_timings
          timed do |context|
            next unless context.node

            builder = RubyLsp::ResponseBuilders::Hover.new
            listener = @addon.create_hover_listener(builder, context, Prism::Dispatcher.new)
            next unless listener

            dispatch_hover(listener, context.node)
          end
        end

        def definition_timings
          timed do |context|
            next unless context.node.is_a?(Prism::CallNode)

            builder = RubyLsp::ResponseBuilders::CollectionResponseBuilder.new
            listener = @addon.create_definition_listener(builder, @uri, context, Prism::Dispatcher.new)
            listener&.on_call_node_enter(context.node)
          end
        end

        private

        def dispatch_hover(listener, node)
          case node
          when Prism::CallNode then listener.on_call_node_enter(node)
          when Prism::SymbolNode then listener.on_symbol_node_enter(node)
          when Prism::StringNode then listener.on_string_node_enter(node)
          when Prism::GlobalVariableReadNode then listener.on_global_variable_read_node_enter(node)
          when Prism::LocalVariableReadNode then listener.on_local_variable_read_node_enter(node)
          when Prism::ConstantReadNode then listener.on_constant_read_node_enter(node)
          when Prism::ConstantPathNode then listener.on_constant_path_node_enter(node)
          end
        end

        def timed
          GC.start
          GC.disable
          samples = @positions.map do |position|
            context = locate(position)
            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            yield context
            Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          end
          samples
        ensure
          GC.enable
        end

        def locate(position)
          RubyLsp::RubyDocument.locate(
            @document.ast,
            position,
            code_units_cache: @document.code_units_cache,
            node_types: LOCATE_TARGETS
          )
        end

        def build_document(source)
          RubyLsp::RubyDocument.new(
            source: source,
            version: 1,
            uri: @uri,
            global_state: RubyLsp::GlobalState.new
          )
        end

        def each_node(node, &block)
          return unless node

          yield node
          node.compact_child_nodes.each { |child| each_node(child, &block) }
        end

        # Request positions: the method name of every call, plus the start of
        # every other node type the add-on handles. Capped and spread evenly so
        # the benchmark stays quick.
        def sample_positions
          offsets = []
          each_node(@document.ast) do |node|
            case node
            when Prism::CallNode
              offsets << node.message_loc.start_offset if node.message_loc
            when Prism::SymbolNode, Prism::StringNode, Prism::GlobalVariableReadNode,
              Prism::LocalVariableReadNode, Prism::ConstantReadNode, Prism::ConstantPathNode
              offsets << node.location.start_offset
            end
          end

          offsets = offsets.uniq.sort
          return [] if offsets.empty?

          stride = (offsets.size / SAMPLE_LIMIT.to_f).ceil
          offsets.each_slice(stride).map(&:first)
        end
      end

      module_function

      def percentile(samples, fraction)
        sorted = samples.sort
        sorted[[(sorted.size * fraction).ceil - 1, 0].max]
      end

      def report(label, samples, budget)
        p50 = percentile(samples, 0.50)
        p95 = percentile(samples, 0.95)
        maximum = samples.max
        status = if budget && p95 > budget
          "FAIL"
        else
          "OK"
        end
        budget_text = budget ? format("budget p95 < %.1f ms", budget * 1000) : "informational"
        format(
          "%-28s p50=%7.3f ms  p95=%7.3f ms  max=%7.3f ms  %-8s %s",
          label, p50 * 1000, p95 * 1000, maximum * 1000, status, budget_text
        )
      end
    end
  end
end

benchmarks = RubyLsp::Dragonruby::Benchmarks
logger = RubyLsp::Dragonruby::Logger.new(StringIO.new)

registry_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
registry = RubyLsp::Dragonruby::Registry.load(logger: logger)
registry_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - registry_started

requests = benchmarks::Requests.new

# Warm up so the first measured request is not dominated by lazy initialization.
requests.completion_timings
requests.hover_timings

completion = requests.completion_timings
hover = requests.hover_timings
definition = requests.definition_timings

abort "add-on logged errors during benchmarking:\n#{requests.error_messages.join("\n")}" if requests.error_messages.any?

scan = nil
benchmarks::SampleWorkspace.with_workspace do |dir|
  tracker = RubyLsp::Dragonruby::StateTracker.new(registry, workspace_path: dir, logger: logger)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  tracker.ensure_workspace_scanned
  scan = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  abort "workspace scan did not collect state" unless tracker.path?("score") && tracker.path?("file_0_key_0")
end

puts "Ruby LSP DragonRuby benchmarks (targets DragonRuby #{registry.metadata.dragonruby_version})"
puts format("%-28s %8.1f ms  informational", "Registry load", registry_elapsed * 1000)
puts benchmarks.report("Completion request p95", completion, benchmarks::PERF_02_BUDGET)
puts benchmarks.report("Hover request p95", hover, benchmarks::PERF_02_BUDGET)
puts benchmarks.report("Definition request p95", definition, nil)
status = if scan < benchmarks::PERF_03_BUDGET
  "OK"
else
  "FAIL"
end
puts format("%-28s %8.3f s   %-8s budget < %.1f s", "Workspace scan (50 files)", scan,
  status, benchmarks::PERF_03_BUDGET)

failures = []
completion_p95 = benchmarks.percentile(completion, 0.95)
hover_p95 = benchmarks.percentile(hover, 0.95)
failures << "completion p95 #{format("%.3f", completion_p95 * 1000)} ms exceeds 10 ms" if
  completion_p95 > benchmarks::PERF_02_BUDGET
failures << "hover p95 #{format("%.3f", hover_p95 * 1000)} ms exceeds 10 ms" if
  hover_p95 > benchmarks::PERF_02_BUDGET
failures << "workspace scan #{format("%.3f", scan)} s exceeds 1 s" if scan >= benchmarks::PERF_03_BUDGET

requests.deactivate

abort("Benchmark budgets failed:\n  #{failures.join("\n  ")}") if failures.any?
