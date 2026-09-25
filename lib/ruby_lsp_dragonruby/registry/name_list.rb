# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      class NameList
        Entry = Data.define(:name, :aliases) do
          def initialize(name:, aliases: [])
            super(name: name, aliases: aliases.freeze)
          end
        end

        attr_reader :id, :entries

        def initialize(id:, entries:)
          @id = id
          @entries = entries.freeze
          freeze
        end

        def entry_names
          @entries.map(&:name)
        end
      end
    end
  end
end
