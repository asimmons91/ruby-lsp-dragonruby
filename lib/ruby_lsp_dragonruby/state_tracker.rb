# frozen_string_literal: true

require "prism"
require "uri"

require_relative "resolver"
require_relative "state_collector"
require_relative "state_store"

module RubyLsp
  module Dragonruby
    # Owns the workspace state store and keeps it in sync.
    #
    # The initial build scans the workspace on first use, once Ruby LSP's index
    # is available for `attr_gtk` roots. Watcher notifications replace a
    # changed file's contributions and drop a deleted file's, and URI-bearing
    # requests refresh the current document from its parsed AST so unsaved
    # edits are visible.
    class StateTracker
      attr_reader :store, :resolver
      attr_accessor :workspace_path

      def initialize(registry, index: nil, workspace_path: nil, logger: nil)
        @registry = registry
        @index = index
        @workspace_path = workspace_path
        @logger = logger
        @store = StateStore.new
        @resolver = Resolver.new(registry, index: index, state_store: @store)
        @collector = StateCollector.new(registry, @resolver)
        @scanned = false
      end

      def ensure_workspace_scanned
        return if @scanned
        return if @index && !@index.initial_indexing_completed

        @scanned = true
        scan_workspace
      rescue => error
        log(error)
      end

      # The structural state path a node reads, if any. Used by hover when a
      # curated entity member shadows a middle segment.
      def state_path_for(node, node_context)
        @collector.state_path_for(node, node_context)
      end

      # Replaces a file's contributions from source text (watcher events and
      # tests).
      def replace_source(uri, source)
        return unless uri && source

        program = Prism.parse(source).value
        @store.replace(uri.to_s, @collector.collect(program, uri))
      rescue => error
        log(error)
      end

      # Replaces a file's contributions from an already parsed document
      # (completion and definition requests).
      def refresh(uri, node_context)
        return unless uri

        program = program_from(node_context)
        return unless program

        @store.replace(uri.to_s, @collector.collect(program, uri))
      rescue => error
        log(error)
      end

      def remove(uri)
        @store.remove(uri.to_s)
      rescue => error
        log(error)
      end

      def entry(path)
        @store.entry(path)
      end

      # Hover does not receive a URI, so it falls back to a URI-less collection
      # of the current AST when the store does not know the path yet.
      def entry_with_context(path, node_context)
        @store.entry(path) || ephemeral_entry(path, node_context)
      end

      def child_names(path = "")
        @store.child_names(path)
      end

      def path?(path)
        @store.path?(path)
      end

      private

      def scan_workspace
        return unless @workspace_path

        files.each do |path|
          uri = URI::Generic.from_path(path: path)
          replace_source(uri, File.read(path))
        rescue SystemCallError, IOError => error
          log(error)
        end
      end

      def files
        Dir.glob(File.join(@workspace_path, "**", "*.rb")).reject { |path| ignored?(path) }
      end

      def ignored?(path)
        relative = path.delete_prefix(@workspace_path).split(File::SEPARATOR)
        relative[0..-2].any? { |dir| %w[vendor node_modules tmp .bundle].include?(dir) }
      end

      def ephemeral_entry(path, node_context)
        program = program_from(node_context)
        return unless program

        entry = nil
        @collector.collect(program).each do |record|
          next unless record.path == path

          entry ||= StateStore::Entry.new(path: path, parent: record.parent)
          entry.add_write(record.site)
        end
        entry
      rescue => error
        log(error)
        nil
      end

      def program_from(node_context)
        nodes = node_context&.instance_variable_get(:@nesting_nodes)
        return unless nodes.is_a?(Array)

        nodes.find { |node| node.is_a?(Prism::ProgramNode) }
      end

      def log(error)
        @logger&.error("#{error.class}: #{error.message}")
      end
    end
  end
end
