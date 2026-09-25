# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      class Metadata
        attr_reader :dragonruby_version, :curated_at, :schema_version

        def initialize(dragonruby_version:, curated_at:, schema_version: 1)
          @dragonruby_version = dragonruby_version
          @curated_at = curated_at
          @schema_version = schema_version
          freeze
        end
      end
    end
  end
end
