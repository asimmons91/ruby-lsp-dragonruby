# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    # Per-add-on settings delivered through Ruby LSP's initialization options
    # (`initializationOptions.addonSettings`). Built per request, so zero
    # configuration falls back to the documented defaults and editors that
    # re-apply options are honored.
    class Settings
      # Identifier users list in the editor's `linters` option to receive
      # DragonRuby diagnostics from the pull request.
      LINTER_ID = "dragonruby"

      ADDON_NAME = "Ruby LSP DragonRuby"

      SETTINGS_KEY = "rubyLspDragonruby"

      def self.from(global_state)
        new(global_state&.settings_for_addon(SETTINGS_KEY))
      end

      def initialize(raw = nil)
        warnings = fetch_hash(raw, "warnings")
        @enabled = boolean(warnings, "enabled", true)
        @primitive_keys = boolean(warnings, "primitiveKeys", false, alias_key: "primitive_keys")
        @unassigned_state_reads = boolean(
          warnings,
          "unassignedStateReads",
          false,
          alias_key: "unassigned_state_reads"
        )
        @allowlist = names(fetch(warnings, "allowlist"))
      end

      def enabled?
        @enabled
      end

      def primitive_keys?
        @primitive_keys
      end

      def unassigned_state_reads?
        @unassigned_state_reads
      end

      attr_reader :allowlist

      private

      def fetch(hash, key)
        return nil unless hash.is_a?(Hash)

        value = hash[key]
        value.nil? ? hash[key.to_sym] : value
      end

      def fetch_hash(hash, key)
        value = fetch(hash, key)
        value.is_a?(Hash) ? value : {}
      end

      def boolean(hash, key, default, alias_key: nil)
        value = fetch(hash, key)
        value = fetch(hash, alias_key) if value.nil? && alias_key

        case value
        when true, false
          value
        when "true"
          true
        when "false"
          false
        else
          default
        end
      end

      def names(value)
        return Set.new unless value.is_a?(Array)

        value.filter_map do |name|
          name.to_s if name.is_a?(String) || name.is_a?(Symbol)
        end.to_set
      end
    end
  end
end
