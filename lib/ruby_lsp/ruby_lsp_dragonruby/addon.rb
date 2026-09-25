# frozen_string_literal: true

require "ruby_lsp/addon"

require_relative "../../ruby_lsp_dragonruby/version"
require_relative "../../ruby_lsp_dragonruby/logger"
require_relative "../../ruby_lsp_dragonruby/registry"
require_relative "../../ruby_lsp_dragonruby/chain"
require_relative "../../ruby_lsp_dragonruby/resolution"
require_relative "../../ruby_lsp_dragonruby/roots"
require_relative "../../ruby_lsp_dragonruby/resolver"
require_relative "../../ruby_lsp_dragonruby/signature"
require_relative "../../ruby_lsp_dragonruby/listeners/completion"
require_relative "../../ruby_lsp_dragonruby/listeners/hover"

module RubyLsp
  module Dragonruby
    class Addon < ::RubyLsp::Addon
      attr_reader :registry

      def initialize(logger: nil)
        super()
        @logger = logger || Logger.new
        @registry = nil
      end

      def name
        "Ruby LSP DragonRuby"
      end

      def version
        VERSION
      end

      def activate(_global_state, _outgoing_queue)
        @registry = Registry.load(logger: @logger)
      rescue => error
        @logger.error("#{error.class}: #{error.message}")
        add_error(error)
      end

      def deactivate
        @registry = nil
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
          logger: @logger
        )
      rescue => error
        @logger.error("#{error.class}: #{error.message}")
      end

      def create_hover_listener(response_builder, node_context, dispatcher)
        return unless @registry

        Listeners::Hover.new(response_builder, @registry, node_context, dispatcher, logger: @logger)
      rescue => error
        @logger.error("#{error.class}: #{error.message}")
      end
    end
  end
end
