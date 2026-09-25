# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestEditDistance < Minitest::Test
      def test_between_counts_edits_and_transpositions
        assert_equal 0, EditDistance.between("keyboard", "keyboard")
        assert_equal 1, EditDistance.between("keybaord", "keyboard")
        assert_equal 1, EditDistance.between("keyboard", "keyboards")
        assert_equal 3, EditDistance.between("kitten", "sitting")
      end

      def test_suggestion_finds_the_close_member
        assert_equal "keyboard", EditDistance.suggestion("keybaord", %w[keyboard mouse])
        assert_equal "sprites", EditDistance.suggestion("spritess", %w[sprites labels])
      end

      def test_suggestion_ignores_distant_candidates
        assert_nil EditDistance.suggestion("keyboard", %w[mouse grid])
        assert_nil EditDistance.suggestion("completely_different", %w[keyboard mouse])
      end

      def test_short_names_only_suggest_matching_first_letter
        assert_nil EditDistance.suggestion("x", %w[y z])
        assert_equal "xy", EditDistance.suggestion("xz", %w[xy])
      end

      def test_suggestion_returns_nil_for_empty_input
        assert_nil EditDistance.suggestion("", %w[keyboard])
        assert_nil EditDistance.suggestion(nil, %w[keyboard])
      end
    end
  end
end
