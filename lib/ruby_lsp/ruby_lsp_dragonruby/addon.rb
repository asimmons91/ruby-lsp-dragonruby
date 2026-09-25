# frozen_string_literal: true

require "ruby_lsp/addon"

require_relative "../../ruby_lsp_dragonruby/version"
require_relative "../../ruby_lsp_dragonruby/logger"
require_relative "../../ruby_lsp_dragonruby/registry"
require_relative "../../ruby_lsp_dragonruby/indexing_enhancement"
require_relative "../../ruby_lsp_dragonruby/chain"
require_relative "../../ruby_lsp_dragonruby/resolution"
require_relative "../../ruby_lsp_dragonruby/roots"
require_relative "../../ruby_lsp_dragonruby/resolver"
require_relative "../../ruby_lsp_dragonruby/signature"
require_relative "../../ruby_lsp_dragonruby/state_tracker"
require_relative "../../ruby_lsp_dragonruby/listeners/completion"
require_relative "../../ruby_lsp_dragonruby/listeners/definition"
require_relative "../../ruby_lsp_dragonruby/listeners/hover"

module RubyLsp
  module Dragonruby
    class Addon < ::RubyLsp::Addon
      attr_reader :registry, :state_tracker

      def initialize(logger: nil)
        super()
        @logger = logger || Logger.new
        @registry = nil
        @index = nil
        @state_tracker = nil
      end

      def name
        "Ruby LSP DragonRuby"
      end

      def version
        VERSION
      end

      def activate(global_state, _outgoing_queue)
        @registry = Registry.load(logger: @logger)
        @index = global_state&.index
        IndexingEnhancement.registry = @registry
        @state_tracker = StateTracker.new(
          @registry,
          index: @index,
          workspace_path: global_state&.workspace_path,
          logger: @logger
        )
      rescue => error
        @logger.error("#{error.class}: #{error.message}")
        add_error(error)
      end

      def deactivate
        IndexingEnhancement.registry = nil
        @registry = nil
        @index = nil
        @state_tracker = nil
        Registry.reset!
      rescue => error
        add_error(error)
      end

      def create_completion_listener(response_builder, node_context, dispatcher, uri)
        return unless @registry

        Listeners::Completion.new(
          response_builder,
          @registry,
          node_context,
          dispatcher,
          uri,
          logger: @logger,
          index: @index,
          state: @state_tracker
        )
      rescue => error
        @logger.error("#{error.class}: #{error.message}")
      end

      def create_hover_listener(response_builder, node_context, dispatcher)
        return unless @registry

        Listeners::Hover.new(
          response_builder,
          @registry,
          node_context,
          dispatcher,
          logger: @logger,
          index: @index,
          state: @state_tracker
        )
      rescue => error
        @logger.error("#{error.class}: #{error.message}")
      end

      def create_definition_listener(response_builder, uri, node_context, dispatcher)
        return unless @registry

        Listeners::Definition.new(
          response_builder,
          @registry,
          node_context,
          dispatcher,
          uri,
          logger: @logger,
          index: @index,
          state: @state_tracker
        )
      rescue => error
        @logger.error("#{error.class}: #{error.message}")
      end

      # File-watcher notifications reach add-ons that define this method. Ruby
      # LSP has already updated its own index for `.rb` changes by this point.
      def workspace_did_change_watched_files(changes)
        return unless @state_tracker && changes.is_a?(Array)

        changes.each do |change|
          uri = URI(change[:uri])
          path = uri.to_standardized_path
          next unless path&.end_with?(".rb")

          apply_state_change(uri, path, change[:type])
        rescue => error
          @logger.error("#{error.class}: #{error.message}")
        end
      rescue => error
        @logger.error("#{error.class}: #{error.message}")
      end

      private

      def apply_state_change(uri, path, type)
        case type
        when Constant::FileChangeType::CREATED, Constant::FileChangeType::CHANGED
          @state_tracker.replace_source(uri, File.read(path))
        when Constant::FileChangeType::DELETED
          @state_tracker.remove(uri)
        end
      rescue Errno::ENOENT
        nil
      end
    end
  end
end
