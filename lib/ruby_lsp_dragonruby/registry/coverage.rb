# frozen_string_literal: true

require "date"
require "yaml"

module RubyLsp
  module Dragonruby
    class Registry
      class Coverage
        Area = Data.define(:id, :title, :docs, :types, :member_count, :missing_types) do
          def covered?
            missing_types.empty? && member_count.positive?
          end
        end

        def self.call(registry, data_dir: Registry::DATA_DIR)
          path = File.join(data_dir, "coverage.yml")
          config = File.exist?(path) ? YAML.safe_load_file(path, permitted_classes: [Date], aliases: true) || {} : {}
          areas = Array(config["areas"]).map do |raw|
            types = Array(raw["types"])
            missing = types.select do |name|
              type = registry.type(name)
              type.nil? || type.all_members.empty?
            end
            member_count = types.sum { |name| registry.type(name)&.all_members&.size || 0 }

            Area.new(
              id: raw["id"],
              title: raw["title"] || raw["id"],
              docs: raw["docs"],
              types: types,
              member_count: member_count,
              missing_types: missing
            )
          end

          new(areas, registry: registry)
        end

        attr_reader :areas

        def initialize(areas, registry:)
          @areas = areas.freeze
          @registry = registry
          @type_rows = registry.types.sort.map { |name, type| "  #{name.ljust(40)} #{type.members.size}" }.freeze
          freeze
        end

        def covered?
          @areas.all?(&:covered?)
        end

        def incomplete
          @areas.reject(&:covered?)
        end

        def to_s
          lines = []
          lines << "DragonRuby registry coverage"
          lines << metadata_line
          lines << ""
          lines << "M1 areas:"
          @areas.each { |area| lines << format_area(area) }
          lines << ""
          lines << "Curated types: #{type_rows.size}"
          lines.concat(type_rows)
          lines.join("\n")
        end

        private

        def metadata_line
          metadata = @registry.metadata
          if metadata
            "  targets DragonRuby #{metadata.dragonruby_version}, curated #{metadata.curated_at}, schema v#{metadata.schema_version}"
          else
            "  metadata unavailable"
          end
        end

        def format_area(area)
          status = area.covered? ? "OK" : "MISSING"
          missing = area.missing_types.empty? ? "" : " missing=[#{area.missing_types.join(", ")}]"
          format(
            "  %-22s types: %-3d members: %-4d %-8s %s%s",
            area.id,
            area.types.size,
            area.member_count,
            status,
            area.docs,
            missing
          )
        end

        attr_reader :type_rows
      end
    end
  end
end
