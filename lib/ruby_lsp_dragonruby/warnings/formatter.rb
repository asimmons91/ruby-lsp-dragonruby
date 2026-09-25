# frozen_string_literal: true

require "ruby_lsp/internal"

require_relative "../settings"
require_relative "analyzer"

module RubyLsp
  module Dragonruby
    module Warnings
      # Pull-diagnostics runner registered with Ruby LSP under
      # `Settings::LINTER_ID` (M0-S3). It is only consulted when the user lists
      # that identifier in the editor's `linters` option, and it never raises
      # into Ruby LSP's diagnostics response.
      class Formatter
        include Requests::Support::Formatter

        def initialize(registry, index: nil, state: nil, global_state: nil, logger: nil)
          @registry = registry
          @index = index
          @state = state
          @global_state = global_state
          @logger = logger
        end

        # The add-on is not a formatter; returning the source keeps selecting it
        # as one harmless.
        def run_formatting(_uri, document)
          document&.source
        end

        def run_range_formatting(_uri, _source, _base_indentation)
          nil
        end

        def run_diagnostic(uri, document)
          settings = Settings.from(@global_state)
          return [] unless settings.enabled? && document

          @state&.ensure_workspace_scanned
          program = document.ast
          @state&.replace_program(uri, program)
          Analyzer.new(
            @registry,
            index: @index,
            state: @state,
            settings: settings,
            logger: @logger
          ).diagnostics(program)
        rescue => error
          log(error)
          []
        end

        private

        def log(error)
          @logger&.error("#{error.class}: #{error.message}")
        end
      end
    end
  end
end
