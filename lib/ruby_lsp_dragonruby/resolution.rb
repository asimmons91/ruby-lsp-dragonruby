# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    # The outcome of resolving an expression to a DragonRuby type.
    #
    # A resolution is confident when it reaches a registry type or a known core
    # type without crossing an `Unknown` return, a missing member, or an
    # unrecognized root. Only confident resolutions backed by a registry type
    # produce completions and hovers.
    class Resolution
      attr_reader :type, :core_type

      def self.unknown
        new
      end

      def self.of_type(type)
        new(type: type)
      end

      def self.of_core(name)
        new(core_type: name)
      end

      def initialize(type: nil, core_type: nil)
        @type = type
        @core_type = core_type
        freeze
      end

      def unknown?
        @type.nil? && @core_type.nil?
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
    end
  end
end
