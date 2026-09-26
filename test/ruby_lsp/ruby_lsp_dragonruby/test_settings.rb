# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestSettings < Minitest::Test
      FakeGlobalState = Struct.new(:settings) do
        def settings_for_addon(name)
          settings&.fetch(name, nil)
        end
      end

      def test_defaults_when_no_settings_exist
        settings = Settings.from(FakeGlobalState.new(nil))

        assert settings.enabled?
        refute settings.primitive_keys?
        refute settings.unassigned_state_reads?
        assert_empty settings.allowlist
      end

      def test_reads_string_keys
        settings = Settings.new(
          "warnings" => {
            "enabled" => false,
            "primitiveKeys" => true,
            "unassignedStateReads" => true,
            "allowlist" => ["inspect", :send]
          }
        )

        refute settings.enabled?
        assert settings.primitive_keys?
        assert settings.unassigned_state_reads?
        assert_equal ["inspect", "send"], settings.allowlist.to_a.sort
      end

      def test_reads_symbol_and_snake_case_keys
        settings = Settings.new(
          warnings: {
            enabled: true,
            primitive_keys: true,
            unassigned_state_reads: true,
            allowlist: [:foo]
          }
        )

        assert settings.enabled?
        assert settings.primitive_keys?
        assert settings.unassigned_state_reads?
        assert_includes settings.allowlist, "foo"
      end

      def test_malformed_values_fall_back_to_defaults
        settings = Settings.new(
          "warnings" => {
            "enabled" => "yes",
            "primitiveKeys" => nil,
            "unassignedStateReads" => 1,
            "allowlist" => "foo"
          }
        )

        assert settings.enabled?
        refute settings.primitive_keys?
        refute settings.unassigned_state_reads?
        assert_empty settings.allowlist
      end

      def test_accepts_string_booleans
        settings = Settings.new("warnings" => {"enabled" => "false"})

        refute settings.enabled?
      end

      def test_from_reads_the_settings_entry
        global_state = FakeGlobalState.new(
          {Settings::SETTINGS_KEY => {"warnings" => {"enabled" => false}}}
        )

        refute Settings.from(global_state).enabled?
      end

      def test_from_ignores_the_addon_name_entry
        global_state = FakeGlobalState.new(
          {Settings::ADDON_NAME => {"warnings" => {"enabled" => false}}}
        )

        assert Settings.from(global_state).enabled?
      end
    end
  end
end
