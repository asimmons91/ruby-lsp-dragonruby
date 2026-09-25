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

        private

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
