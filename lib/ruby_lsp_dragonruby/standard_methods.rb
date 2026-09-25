# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    # Detects methods that stock Ruby already defines on a core class. The
    # add-on runs on CRuby, so reflection answers this precisely for the
    # standard library while the registry curates DragonRuby's additions.
    #
    # Used only to filter completion candidates (REQ-M6-06): a curated member
    # that stock Ruby also defines (`clamp`, `fdiv`, ...) still participates in
    # resolution and hover, but it is never offered as a DragonRuby addition.
    module StandardMethods
      @instance_cache = {}

      class << self
        def standard_instance_method?(core_type, name)
          names = @instance_cache[core_type] ||= instance_method_names(core_type)
          names.include?(name.to_sym)
        end

        def standard_class_method?(core_type, name)
          klass = class_for(core_type)
          return false unless klass

          # Public only: private Kernel methods (`rand`, `select`) are not
          # callable with an explicit class receiver in stock Ruby, so curated
          # DragonRuby class extensions may still be offered for those names.
          klass.respond_to?(name)
        end

        # Methods every Ruby object responds to, so undefined-member warnings
        # never fire for `inspect`, `class`, `send`, `respond_to?`, and the
        # like on registry types that have no CRuby counterpart (REQ-M7-01).
        def standard_object_method?(name)
          object_method_names.include?(name.to_sym)
        end

        private

        def object_method_names
          @object_method_names ||= Set.new(
            Object.instance_methods + Object.private_instance_methods + Object.protected_instance_methods +
              BasicObject.instance_methods + BasicObject.private_instance_methods + BasicObject.protected_instance_methods
          )
        end

        def instance_method_names(core_type)
          klass = class_for(core_type)
          return Set.new unless klass

          Set.new(klass.instance_methods + klass.private_instance_methods)
        end

        def class_for(name)
          Object.const_get(name)
        rescue NameError
          nil
        end
      end
    end
  end
end
