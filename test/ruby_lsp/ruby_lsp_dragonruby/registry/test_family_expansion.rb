# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestFamilyExpansion < Minitest::Test
      include RegistryTestHelper

      def test_substitutes_names_and_merges_aliases
        list = Registry::NameList.new(
          id: "keys",
          entries: [Registry::NameList::Entry.new(name: "a", aliases: ["ay"])]
        )
        spec = {
          "generates" => [
            {
              "names" => "keys",
              "members" => [
                {"name" => "{{name}}", "doc" => "The {{name}} key", "aliases" => ["x"]}
              ]
            }
          ]
        }

        members = Registry::FamilyExpansion.expand(spec, {"keys" => list})

        assert_equal 1, members.size
        assert_equal "a", members[0]["name"]
        assert_equal "The a key", members[0]["doc"]
        assert_equal %w[x ay], members[0]["aliases"]
      end

      def test_unknown_name_list_yields_no_members
        spec = {"generates" => [{"names" => "missing", "members" => [{"name" => "{{name}}"}]}]}
        assert_empty Registry::FamilyExpansion.expand(spec, {})
      end

      def test_hand_written_members_are_preserved
        spec = {"members" => [{"name" => "given"}], "generates" => []}
        assert_equal ["given"], Registry::FamilyExpansion.expand(spec, {}).map { |member| member["name"] }
      end
    end
  end
end
