# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      module FamilyExpansion
        module_function

        def expand(spec, name_lists)
          members = Array(spec["members"]).dup
          Array(spec["generates"]).each do |generation|
            next unless generation.is_a?(Hash)

            name_list = name_lists[generation["names"]]
            next unless name_list

            templates = Array(generation["members"])
            name_list.entries.each do |entry|
              templates.each do |template|
                next unless template.is_a?(Hash)

                members << instantiate(template, entry)
              end
            end
          end
          members
        end

        def instantiate(template, entry)
          member = deep_substitute(template, "name" => entry.name)
          aliases = Array(member["aliases"]) + entry.aliases
          aliases = aliases.uniq
          aliases.any? ? member.merge("aliases" => aliases) : member
        end

        def deep_substitute(value, substitutions)
          case value
          when String
            substitutions.reduce(value) do |result, (key, replacement)|
              result.gsub("{{#{key}}}", replacement)
            end
          when Array
            value.map { |item| deep_substitute(item, substitutions) }
          when Hash
            value.transform_values { |item| deep_substitute(item, substitutions) }
          else
            value
          end
        end
      end
    end
  end
end
