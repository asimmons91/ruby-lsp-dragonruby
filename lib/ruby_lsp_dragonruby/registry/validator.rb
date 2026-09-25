# frozen_string_literal: true

require "date"

module RubyLsp
  module Dragonruby
    class Registry
      class Validator
        MEMBER_KINDS = %w[attribute method].freeze
        PARAM_KINDS = %w[required optional keyword rest block].freeze

        Result = Data.define(:issues, :types, :schemas, :metadata, :name_lists)

        def initialize(documents)
          @documents = documents
          @issues = []
          @types = {}
          @schemas = {}
          @name_lists = {}
          @type_names = Set.new
          @schema_names = Set.new
        end

        def call
          collect_name_lists
          collect_types
          collect_schemas
          @type_names = @types.keys.to_set
          @schema_names = @schemas.keys.to_set
          metadata = validate_metadata

          specs = prune_types
          schema_specs = prune_schemas

          Result.new(
            issues: @issues,
            types: specs,
            schemas: schema_specs,
            metadata: metadata,
            name_lists: @name_lists
          )
        end

        private

        def collect_name_lists
          @documents.name_list_entries.each do |entry|
            raw = entry.raw
            id = raw["id"]
            path = path_for(entry, "names")
            unless id.is_a?(String) && !id.empty?
              issue(path, "missing required field `id`")
              next
            end
            if @name_lists.key?(id)
              issue(path_for(entry, "names[#{id}]"), "duplicate name list `#{id}`")
              next
            end

            entries = Array(raw["entries"]).filter_map do |item|
              build_name_entry(item, path_for(entry, "names[#{id}]"))
            end
            @name_lists[id] = NameList.new(id: id, entries: entries)
          end
        end

        def build_name_entry(item, path)
          case item
          when String
            return nil if item.empty?

            NameList::Entry.new(name: item)
          when Hash
            name = item["name"]
            unless name.is_a?(String) && !name.empty?
              issue(path, "name list entry is missing a `name`")
              return nil
            end

            aliases = item["aliases"]
            if aliases && !aliases.is_a?(Array)
              issue(path, "`aliases` for `#{name}` must be a list")
              aliases = []
            end
            NameList::Entry.new(name: name, aliases: Array(aliases).map(&:to_s))
          else
            issue(path, "name list entry must be a string or a mapping")
            nil
          end
        end

        def collect_types
          @documents.type_entries.each do |entry|
            raw = entry.raw
            unless raw.is_a?(Hash)
              issue(path_for(entry, "types"), "type entry must be a mapping")
              next
            end

            name = raw["name"]
            path = path_for(entry, "types[#{name || "?"}]")
            unless name.is_a?(String) && !name.empty?
              issue(path, "missing required field `name`")
              next
            end
            if @types.key?(name)
              issue(path, "duplicate type name `#{name}`")
              next
            end

            @types[name] = entry
          end
        end

        def collect_schemas
          @documents.schema_entries.each do |entry|
            raw = entry.raw
            unless raw.is_a?(Hash)
              issue(path_for(entry, "schemas"), "schema entry must be a mapping")
              next
            end

            name = raw["name"]
            path = path_for(entry, "schemas[#{name || "?"}]")
            unless name.is_a?(String) && !name.empty?
              issue(path, "missing required field `name`")
              next
            end
            if @schemas.key?(name)
              issue(path, "duplicate schema name `#{name}`")
              next
            end

            @schemas[name] = entry
          end
        end

        def validate_metadata
          entry = @documents.metadata_entry
          unless entry
            issue("metadata", "missing registry metadata (dragonruby_version and curated_at)")
            return nil
          end

          raw = entry.raw
          path = path_for(entry, "metadata")
          version = raw["dragonruby_version"]
          curated_at = raw["curated_at"]
          curated_at = curated_at.iso8601 if curated_at.is_a?(Date)
          schema_version = raw["schema_version"] || 1

          valid = true
          unless version.is_a?(String) && !version.empty?
            issue(path, "missing required field `dragonruby_version`")
            valid = false
          end

          unless iso_date?(curated_at)
            issue(path, "`curated_at` must be an ISO 8601 date")
            valid = false
          end

          unless schema_version.is_a?(Integer) && schema_version.positive?
            issue(path, "`schema_version` must be a positive integer")
            valid = false
          end

          return nil unless valid

          Metadata.new(dragonruby_version: version, curated_at: curated_at, schema_version: schema_version)
        end

        def iso_date?(value)
          return false unless value.is_a?(String)

          Date.iso8601(value)
          true
        rescue Date::Error
          false
        end

        def prune_types
          specs = {}
          @types.each do |name, entry|
            specs[name] = prune_type(entry)
          end

          resolve_parents(specs)
          specs
        end

        def prune_type(entry)
          raw = entry.raw
          name = raw["name"]
          path = path_for(entry, "types[#{name}]")
          spec = {"name" => name}

          spec["doc"] = raw["doc"] if raw["doc"].is_a?(String)
          spec["parent"] = raw["parent"] if raw["parent"].is_a?(String)
          if raw.key?("parent") && !raw["parent"].is_a?(String)
            issue(path, "`parent` must be a type name")
          end
          spec["open"] = boolean_field(raw, "open", path, default: false)
          spec["incomplete"] = boolean_field(raw, "incomplete", path, default: false)

          accepts = raw["accepts_primitive"]
          if accepts
            if accepts.is_a?(String) && @schema_names.include?(accepts)
              spec["accepts_primitive"] = accepts
            else
              issue(path, "dangling accepts_primitive reference `#{accepts}`")
            end
          end

          validate_generates(raw, path)
          members = FamilyExpansion.expand(raw, @name_lists)
          spec["members"] = validate_members(members, path)
          spec
        end

        def validate_generates(raw, type_path)
          Array(raw["generates"]).each_with_index do |generation, index|
            path = "#{type_path}.generates[#{index}]"
            unless generation.is_a?(Hash)
              issue(path, "generates entry must be a mapping")
              next
            end

            names = generation["names"]
            unless names.is_a?(String) && @name_lists.key?(names)
              issue(path, "dangling name list reference `#{names}`")
            end
            unless generation["members"].is_a?(Array)
              issue(path, "`members` must be a list")
            end
          end
        end

        def boolean_field(raw, key, path, default:)
          return default unless raw.key?(key)

          value = raw[key]
          unless [true, false].include?(value)
            issue(path, "`#{key}` must be true or false")
            return default
          end

          value
        end

        def validate_members(members, type_path)
          candidates = []
          seen_names = {}

          members.each_with_index do |member, index|
            unless member.is_a?(Hash)
              issue("#{type_path}.members[#{index}]", "member must be a mapping")
              next
            end

            name = member["name"]
            path = "#{type_path}.members[#{name || index}]"
            unless name.is_a?(String) && !name.empty?
              issue(path, "missing required field `name`")
              next
            end
            if seen_names.key?(name)
              issue(path, "duplicate member name `#{name}`")
              next
            end

            kind = member["kind"]
            unless MEMBER_KINDS.include?(kind)
              issue(path, "invalid kind `#{kind}`")
              next
            end
            if kind == "attribute" && Array(member["params"]).any?
              issue(path, "attribute cannot declare params")
              next
            end
            unless member["doc"].is_a?(String) && !member["doc"].strip.empty?
              issue(path, "missing required field `doc`")
              next
            end

            returns = resolve_expression(member["returns"], "#{path}.returns")
            next unless returns

            params = validate_params(member["params"], path)
            next if params == :invalid

            candidates << {
              "name" => name,
              "kind" => kind.to_sym,
              "returns" => returns,
              "params" => params,
              "doc" => member["doc"],
              "docs_url" => member["docs_url"],
              "aliases" => member["aliases"],
              "path" => path
            }
            seen_names[name] = true
          end

          apply_aliases(candidates, seen_names)
        end

        def apply_aliases(candidates, seen_names)
          taken = seen_names.dup
          candidates.map do |candidate|
            aliases = normalize_aliases(candidate, taken)
            candidate["aliases"] = aliases
            candidate.delete("path")
            taken = taken.merge(aliases.to_h { |value| [value, true] })
            candidate
          end
        end

        def normalize_aliases(candidate, taken)
          raw = candidate["aliases"]
          return [] unless raw

          unless raw.is_a?(Array)
            issue(candidate["path"], "`aliases` must be a list")
            return []
          end

          raw.filter_map do |value|
            unless value.is_a?(String) && !value.empty?
              issue(candidate["path"], "alias values must be non-empty strings")
              next
            end
            if taken.key?(value)
              issue(candidate["path"], "alias `#{value}` is already a member or alias", :warning)
              next
            end

            value
          end
        end

        def validate_params(params, member_path)
          return [] if params.nil?

          unless params.is_a?(Array)
            issue(member_path, "`params` must be a list")
            return :invalid
          end

          params.map do |param|
            unless param.is_a?(Hash)
              issue(member_path, "param must be a mapping")
              return :invalid
            end

            kind = param["kind"]
            unless PARAM_KINDS.include?(kind)
              issue(member_path, "invalid param kind `#{kind}`")
              return :invalid
            end

            name = param["name"]
            if name.nil? && kind != "block"
              issue(member_path, "param `#{kind}` is missing a `name`")
              return :invalid
            end
            if name && (!name.is_a?(String) || name.empty?)
              issue(member_path, "param name must be a non-empty string")
              return :invalid
            end

            type = resolve_expression(param["type"], "#{member_path}.params[#{name || kind}]")
            return :invalid unless type

            {"name" => name, "kind" => kind.to_sym, "type" => type}
          end
        end

        def resolve_parents(specs)
          specs.each_value do |spec|
            parent = spec["parent"]
            next unless parent
            next if specs.key?(parent)

            issue("types[#{spec["name"]}]", "unresolved parent type `#{parent}`")
            spec["parent"] = nil
          end

          specs.each_value do |spec|
            name = spec["name"]
            seen = []
            cursor = spec["parent"]
            while cursor && specs.key?(cursor)
              if cursor == name || seen.include?(cursor)
                issue("types[#{name}]", "cyclic parent chain detected")
                spec["parent"] = nil
                break
              end
              seen << cursor
              cursor = specs[cursor]["parent"]
            end
          end
        end

        def prune_schemas
          @schemas.transform_values { |entry| prune_schema(entry) }
        end

        def prune_schema(entry)
          raw = entry.raw
          name = raw["name"]
          path = path_for(entry, "schemas[#{name}]")
          spec = {"name" => name}

          if raw.key?("primitive_marker")
            marker = raw["primitive_marker"]
            if marker.is_a?(String) || marker.is_a?(Symbol)
              spec["primitive_marker"] = marker.to_s
            else
              issue(path, "`primitive_marker` must be a value")
            end
          end

          spec["keys"] = validate_primitive_keys(raw["keys"], path)
          spec
        end

        def validate_primitive_keys(keys, schema_path)
          return [] if keys.nil?

          unless keys.is_a?(Array)
            issue(schema_path, "`keys` must be a list")
            return []
          end

          seen = {}
          keys.filter_map do |key|
            unless key.is_a?(Hash)
              issue(schema_path, "primitive key must be a mapping")
              next
            end

            name = key["name"]
            path = "#{schema_path}.keys[#{name || "?"}]"
            unless name.is_a?(String) && !name.empty?
              issue(path, "missing required field `name`")
              next
            end
            if seen.key?(name)
              issue(path, "duplicate primitive key `#{name}`")
              next
            end

            type = resolve_expression(key["type"], "#{path}.type")
            next unless type

            unless key["doc"].is_a?(String) && !key["doc"].strip.empty?
              issue(path, "missing required field `doc`")
              next
            end

            allowed = key["allowed_values"]
            if allowed && !allowed.is_a?(Array)
              issue(path, "`allowed_values` must be a list")
              allowed = nil
            end

            seen[name] = true
            entry = {"name" => name, "type" => type, "doc" => key["doc"], "path" => path}
            entry["default"] = key["default"] if key.key?("default")
            entry["allowed_values"] = allowed if allowed
            entry.delete("path")
            entry
          end
        end

        def resolve_expression(value, path)
          names =
            case value
            when String
              [value]
            when Array
              value
            else
              issue(path, "type must be a name or a list of names")
              return nil
            end

          if names.empty?
            issue(path, "type list cannot be empty")
            return nil
          end

          names.each do |name|
            next if name.is_a?(String) && known_type_name?(name)

            issue(path, "unresolved type `#{name}`")
            return nil
          end

          names
        end

        def known_type_name?(name)
          name == UNKNOWN || CORE_TYPES.include?(name) || @type_names.include?(name)
        end

        def path_for(entry, suffix)
          "#{File.basename(entry.file)}: #{suffix}"
        end

        def issue(path, message, severity = :error)
          @issues << Issue.new(path: path, message: message, severity: severity)
          nil
        end
      end
    end
  end
end
