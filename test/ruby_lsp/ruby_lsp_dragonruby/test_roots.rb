# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Dragonruby
    class TestRoots < Minitest::Test
      include RegistryTestHelper

      TYPES = <<~YAML
        types:
          - name: GTK::Args
            members: []
          - name: GTK::Runtime
            members: []
          - name: Geometry
            members: []
      YAML

      def setup
        @registry = load_registry({"metadata.yml" => METADATA, "types.yml" => TYPES})
        @roots = Roots.new(@registry)
      end

      def test_parameter_root_requires_a_local_variable
        local = Prism.parse("def tick(args)\n  args\nend").value.statements.body.first.body.body.first
        assert_equal "GTK::Args", @roots.resolve(local).name
      end

      def test_parameter_root_does_not_match_method_calls
        call = Prism.parse("args").value.statements.body.first

        assert_instance_of Prism::CallNode, call
        assert_nil @roots.resolve(call)
      end

      def test_global_roots
        assert_equal "GTK::Runtime", @roots.resolve(Prism.parse("$gtk").value.statements.body.first).name
        assert_equal "GTK::Args", @roots.resolve(Prism.parse("$args").value.statements.body.first).name
        assert_nil @roots.resolve(Prism.parse("$stdout").value.statements.body.first)
      end

      def test_registry_constant_roots
        geometry = Prism.parse("Geometry").value.statements.body.first
        path = Prism.parse("GTK::Args").value.statements.body.first

        assert_equal "Geometry", @roots.resolve(geometry).name
        assert_equal "GTK::Args", @roots.resolve(path).name
        assert_nil @roots.resolve(Prism.parse("Nope").value.statements.body.first)
      end

      def test_default_strategies_cover_parameter_global_and_constant
        assert_equal [Roots::Parameter, Roots::Global, Roots::RegistryConstant], Roots::DEFAULT_STRATEGIES
      end
    end
  end
end
