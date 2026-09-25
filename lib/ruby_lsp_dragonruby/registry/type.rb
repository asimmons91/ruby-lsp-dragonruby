# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      class Type
        attr_reader :name, :parent_name, :members, :all_members, :accepts_primitive, :ancestors, :doc

        def initialize(name:, parent_name: nil, members: [], accepts_primitive: nil, open: false,
          incomplete: false, doc: nil, ancestors: [])
          @name = name
          @parent_name = parent_name
          @members = members.freeze
          @ancestors = ancestors.freeze
          @accepts_primitive = accepts_primitive
          @open = open
          @incomplete = incomplete
          @doc = doc
          @members_by_name = @members.to_h { |member| [member.name, member] }.freeze
          @all_members = (members + ancestors.flat_map(&:members)).uniq(&:name).freeze
          @all_members_by_name = @all_members.to_h { |member| [member.name, member] }.freeze
          freeze
        end

        def member(name)
          @all_members_by_name[name]
        end

        def member?(name)
          @all_members_by_name.key?(name)
        end

        def own_member(name)
          @members_by_name[name]
        end

        def open?
          @open
        end

        def incomplete?
          @incomplete
        end
      end
    end
  end
end
