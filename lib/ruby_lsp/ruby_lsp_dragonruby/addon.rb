# frozen_string_literal: true

require "ruby_lsp/addon"

require_relative "../../ruby_lsp_dragonruby/version"
require_relative "../../ruby_lsp_dragonruby/logger"
require_relative "../../ruby_lsp_dragonruby/registry"

module RubyLsp
  module Dragonruby
    class Addon < ::RubyLsp::Addon
      def initialize(logger: nil)
        super()
        @logger = logger || Logger.new
      end

      def name
        "Ruby LSP DragonRuby"
      end

      def version
        VERSION
      end

      def activate(_global_state, _outgoing_queue)
        Registry.load(logger: @logger)
      rescue => error
        @logger.error("#{error.class}: #{error.message}")
        add_error(error)
      end

      def deactivate
        Registry.reset!
      rescue => error
        add_error(error)
      end
    end
  end
end
