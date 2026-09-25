# frozen_string_literal: true

require_relative "../edit_distance"
require_relative "../settings"
require_relative "../standard_methods"

module RubyLsp
  module Dragonruby
    module Warnings
      # Decides whether a call on a confidently resolved registry type names a
      # member that does not exist (REQ-M7-01) and builds the warning message
      # with an edit-distance suggestion (REQ-M7-03).
      #
      # Shared by the diagnostics analyzer and the hover fallback so both agree
      # on when a member is undefined.
      class UndefinedMember
        def initialize(registry, index: nil, settings: nil)
          @registry = registry
          @index = index
          @settings = settings || Settings.new
        end

        # Returns the warning message for `name` on `type`, or nil when the
        # member is known, the type is exempt (`open`, `incomplete`, a core
        # extension), or the name is allowlisted.
        def warning_for(type, name)
          return nil unless @settings.enabled?
          return nil if type.nil? || name.nil? || name.empty?
          return nil if type.open? || type.incomplete? || type.core_extension?
          return nil if @settings.allowlist.include?(name)
          return nil if type.member?(name)
          return nil if core_backing_method?(type, name)
          return nil if indexed?(type, name)
          return nil if StandardMethods.standard_object_method?(name)

          message(type, name)
        end

        def message(type, name)
          text = "`#{name}` is not a known member of `#{type.name}` in DragonRuby #{version}."
          suggestion = EditDistance.suggestion(name, candidates(type))
          text += " Did you mean `#{suggestion}`?" if suggestion
          text
        end

        private

        # A type documented as a core collection (`Array`, `Hash`, ...) also
        # responds to that class's standard methods, so `args.audio.length` and
        # `args.outputs.sprites.size` never warn.
        def core_backing_method?(type, name)
          backing = type.core_backing
          backing && StandardMethods.standard_instance_method?(backing, name)
        end

        # Reopening a DragonRuby class in the workspace defines the member for
        # Ruby LSP's index, which suppresses the warning (REQ-M7-01).
        def indexed?(type, name)
          return false unless @index

          !@index.resolve_method(name, type.name).nil?
        rescue
          false
        end

        def candidates(type)
          type.all_members.flat_map(&:signatures).uniq
        end

        def version
          @registry.metadata&.dragonruby_version
        end
      end
    end
  end
end
