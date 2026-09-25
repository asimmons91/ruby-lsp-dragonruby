# frozen_string_literal: true

require "date"
require "yaml"

module RubyLsp
  module Dragonruby
    class Registry
      class Coverage
        Area = Data.define(
          :id, :title, :docs, :types, :member_count, :missing_types,
          :schemas, :missing_schemas, :macros, :missing_macros
        ) do
          def covered?
            return false unless missing_types.empty? && missing_schemas.empty? && missing_macros.empty?

            (types.any? && member_count.positive?) || schemas.any? || macros.any?
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
            schemas = Array(raw["schemas"])
            missing_schemas = schemas.select do |name|
              schema = registry.schema(name)
              schema.nil? || schema.keys.empty?
            end
            macros = Array(raw["macros"])
            missing_macros = macros.select do |name|
              macro = registry.macro(name)
              macro.nil? || macro.accessors.empty?
            end

            Area.new(
              id: raw["id"],
              title: raw["title"] || raw["id"],
              docs: raw["docs"],
              types: types,
              member_count: member_count,
              missing_types: missing,
              schemas: schemas,
              missing_schemas: missing_schemas,
              macros: macros,
              missing_macros: missing_macros
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
          lines << "Coverage areas:"
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
          missing = []
          missing << "missing=[#{area.missing_types.join(", ")}]" if area.missing_types.any?
          missing << "missing schemas=[#{area.missing_schemas.join(", ")}]" if area.missing_schemas.any?
          missing << "missing macros=[#{area.missing_macros.join(", ")}]" if area.missing_macros.any?
          format(
            "  %-22s types: %-3d schemas: %-3d macros: %-3d members: %-4d %-8s %s %s",
            area.id,
            area.types.size,
            area.schemas.size,
            area.macros.size,
            area.member_count,
            status,
            area.docs,
            missing.join(" ")
          )
        end

        attr_reader :type_rows
      end
    end
  end
end
