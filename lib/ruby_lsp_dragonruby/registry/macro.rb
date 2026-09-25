# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      # A class-level DragonRuby DSL macro (`attr_gtk`, `attr_sprite`, ...).
      #
      # A macro maps to an accessor list: either declared explicitly in the
      # data or derived from a primitive schema. The indexing enhancement
      # registers every accessor on classes that call the macro, and the
      # resolver uses `marker` to recognize those classes.
      class Macro
        attr_reader :name, :aliases, :accessors, :doc, :primitive

        def initialize(name:, accessors: [], aliases: [], doc: nil, primitive: nil)
          @name = name
          @aliases = aliases.freeze
          @accessors = accessors.freeze
          @doc = doc
          @primitive = primitive
          @accessors_by_name = @accessors.to_h { |accessor| [accessor.name, accessor] }.freeze
          freeze
        end

        def accessor(name)
          @accessors_by_name[name]
        end

        def accessor?(name)
          @accessors_by_name.key?(name)
        end

        # An HTML comment is invisible in rendered hover content, so the
        # sentinel can tag every generated accessor without changing what
        # users see.
        def comment_tag
          "<!-- dragonruby:#{@name} -->"
        end

        def all_names
          [@name, *@aliases]
        end
      end
    end
  end
end
