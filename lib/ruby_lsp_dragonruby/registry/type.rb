# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      class Type
        attr_reader :name, :parent_name, :members, :all_members, :accepts_primitive, :ancestors, :doc

        def initialize(name:, parent_name: nil, members: [], accepts_primitive: nil, open: false,
          incomplete: false, core_extension: false, doc: nil, ancestors: [])
          @name = name
          @parent_name = parent_name
          @members = members.freeze
          @ancestors = ancestors.freeze
          @accepts_primitive = accepts_primitive&.freeze
          @open = open
          @incomplete = incomplete
          @core_extension = core_extension
          @doc = doc
          @members_by_name = index_members(@members)
          @all_members = (members + ancestors.flat_map(&:members)).uniq(&:name).freeze
          @all_members_by_name = index_members(@all_members)
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

        # A type that curates DragonRuby's additions to a core Ruby class
        # (`Numeric`, `Hash`, ...) rather than a DragonRuby-owned type.
        def core_extension?
          @core_extension
        end

        private

        def index_members(members)
          members.each_with_object({}) do |member, index|
            ([member.name] + member.aliases).each do |name|
              index[name] ||= member
            end
          end.freeze
        end
      end
    end
  end
end
