# frozen_string_literal: true

require "date"
require "yaml"

module RubyLsp
  module Dragonruby
    class Registry
      class Loader
        Documents = Data.define(:type_entries, :schema_entries, :macro_entries, :name_list_entries, :metadata_entry)
        Entry = Data.define(:file, :raw)

        def initialize(data_dir:, logger: nil)
          @data_dir = data_dir
          @logger = logger
          @loader_issues = []
        end

        def load
          result = validation_result
          report(result.issues)
          build_registry(result)
        end

        def validation_issues
          result = validation_result
          report(result.issues)
          result.issues
        end

        private

        def validation_result
          @validation_result ||= begin
            result = Validator.new(read_documents).call
            if @loader_issues.empty?
              result
            else
              Validator::Result.new(
                issues: @loader_issues + result.issues,
                types: result.types,
                schemas: result.schemas,
                macros: result.macros,
                metadata: result.metadata,
                name_lists: result.name_lists
              )
            end
          end
        end

        def read_documents
          type_entries = []
          schema_entries = []
          macro_entries = []
          name_list_entries = []
          metadata_entry = nil

          Dir.glob(File.join(@data_dir, "**", "*.yml")).sort.each do |file|
            data = load_file(file)
            next unless data.is_a?(Hash)

            if data.key?("dragonruby_version")
              if metadata_entry
                @loader_issues << Issue.new(
                  path: File.basename(file),
                  message: "duplicate registry metadata document"
                )
              else
                metadata_entry = Entry.new(file: file, raw: data)
              end
            end
            Array(data["types"]).each { |raw| type_entries << Entry.new(file: file, raw: raw) }
            Array(data["schemas"]).each { |raw| schema_entries << Entry.new(file: file, raw: raw) }
            Array(data["macros"]).each { |raw| macro_entries << Entry.new(file: file, raw: raw) }

            names = data["names"]
            if names.is_a?(Hash)
              names.each do |id, entries|
                name_list_entries << Entry.new(file: file, raw: {"id" => id, "entries" => entries})
              end
            elsif names
              name_list_entries << Entry.new(file: file, raw: {"id" => nil, "entries" => names})
            end
          end

          Documents.new(
            type_entries: type_entries,
            schema_entries: schema_entries,
            macro_entries: macro_entries,
            name_list_entries: name_list_entries,
            metadata_entry: metadata_entry
          )
        end

        def load_file(file)
          YAML.safe_load_file(file, permitted_classes: [Date, Symbol], aliases: true)
        rescue Psych::Exception => error
          @loader_issues << Issue.new(
            path: File.basename(file),
            message: "could not parse YAML: #{error.message}"
          )
          nil
        end

        def build_registry(result)
          schemas = build_schemas(result.schemas)
          Registry.new(
            metadata: result.metadata,
            types: build_types(result.types),
            schemas: schemas,
            macros: build_macros(result.macros, schemas)
          )
        end

        def build_types(specs)
          built = {}
          specs.each_key do |name|
            build_type(name, specs, built)
          end
          built
        end

        def build_type(name, specs, built)
          return built[name] if built.key?(name)

          spec = specs.fetch(name)
          parent_name = spec["parent"]
          ancestors = []
          if parent_name && specs.key?(parent_name)
            parent = build_type(parent_name, specs, built)
            ancestors = [parent, *parent.ancestors]
          end

          built[name] = Type.new(
            name: name,
            parent_name: parent_name,
            members: build_members(spec["members"]),
            accepts_primitive: spec["accepts_primitive"],
            open: spec["open"] || false,
            incomplete: spec["incomplete"] || false,
            doc: spec["doc"],
            ancestors: ancestors
          )
        end

        def build_members(raw_members)
          Array(raw_members).map do |raw|
            Member.new(
              name: raw["name"],
              kind: raw["kind"],
              params: Array(raw["params"]).map do |param|
                Param.new(name: param["name"], kind: param["kind"], type: Returns.new(param["type"]))
              end,
              returns: Returns.new(raw["returns"]),
              doc: raw["doc"],
              docs_url: raw["docs_url"],
              aliases: Array(raw["aliases"])
            )
          end
        end

        def build_schemas(specs)
          specs.transform_values do |spec|
            PrimitiveSchema.new(
              name: spec["name"],
              primitive_marker: spec["primitive_marker"],
              keys: Array(spec["keys"]).map { |raw| build_primitive_key(raw) }
            )
          end
        end

        def build_macros(specs, schemas)
          specs.transform_values do |spec|
            primitive = spec["primitive"]
            accessors = if primitive
              schema = schemas[primitive]
              schema ? schema.keys.map { |key| build_accessor(key) } : []
            else
              Array(spec["accessors"]).map { |raw| build_accessor_from_spec(raw) }
            end

            Macro.new(
              name: spec["name"],
              aliases: Array(spec["aliases"]),
              doc: spec["doc"],
              primitive: primitive,
              accessors: accessors
            )
          end
        end

        def build_accessor(key)
          Accessor.new(name: key.name, returns: key.type, doc: key.doc)
        end

        def build_accessor_from_spec(raw)
          Accessor.new(
            name: raw["name"],
            returns: Returns.new(raw["returns"]),
            doc: raw["doc"]
          )
        end

        def build_primitive_key(raw)
          PrimitiveKey.new(
            name: raw["name"],
            type: Returns.new(raw["type"]),
            doc: raw["doc"],
            default: raw.key?("default") ? raw["default"] : UNSET,
            allowed_values: raw["allowed_values"]
          )
        end

        def report(issues)
          return unless @logger

          issues.each do |issue|
            if issue.error?
              @logger.error(issue.to_s)
            else
              @logger.warn(issue.to_s)
            end
          end
        end
      end
    end
  end
end
