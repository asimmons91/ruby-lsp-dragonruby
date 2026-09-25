# frozen_string_literal: true

require_relative "ruby_lsp_dragonruby/version"
require_relative "ruby_lsp_dragonruby/logger"
require_relative "ruby_lsp_dragonruby/registry"
require_relative "ruby_lsp_dragonruby/chain"
require_relative "ruby_lsp_dragonruby/local_aliases"
require_relative "ruby_lsp_dragonruby/macro_lookup"
require_relative "ruby_lsp_dragonruby/primitive_context"
require_relative "ruby_lsp_dragonruby/resolution"
require_relative "ruby_lsp_dragonruby/roots"
require_relative "ruby_lsp_dragonruby/resolver"
require_relative "ruby_lsp_dragonruby/signature"
require_relative "ruby_lsp_dragonruby/state_collector"
require_relative "ruby_lsp_dragonruby/state_store"
require_relative "ruby_lsp_dragonruby/state_tracker"

module RubyLsp
  module Dragonruby
    class Error < StandardError; end
  end
end
