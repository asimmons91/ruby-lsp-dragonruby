# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    # The outcome of resolving an expression to a DragonRuby type, a known
    # core type, or a dynamic `args.state` path.
    #
    # A resolution is confident when it reaches a registry type, a known core
    # type, or a state path without crossing an `Unknown` return, a missing
    # member, or an unrecognized root. Registry types produce completions and
    # hovers; state paths are answered from the workspace state store.
    class Resolution
      attr_reader :type, :core_type, :state_path

      def self.unknown
        new
      end

      def self.of_type(type)
        new(type: type)
      end

      def self.of_core(name)
        new(core_type: name)
      end

      def self.of_state(path)
        new(state_path: path)
      end

      def initialize(type: nil, core_type: nil, state_path: nil)
        @type = type
        @core_type = core_type
        @state_path = state_path
        freeze
      end

      def unknown?
        @type.nil? && @core_type.nil? && @state_path.nil?
      end

      def confident?
        !unknown?
      end

      def resolved_type?
        !@type.nil?
      end

      def core?
        !@core_type.nil?
      end

      def state_path?
        !@state_path.nil?
      end
    end
  end
end
