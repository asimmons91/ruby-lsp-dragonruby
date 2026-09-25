# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    # Formats curated members as Ruby-ish signatures for hover titles and
    # completion details.
    module Signature
      module_function

      def of(member)
        return member.name if member.attribute?

        "#{member.name}(#{params(member)})"
      end

      def params(member)
        member.params.map { |param| param_text(param) }.join(", ")
      end

      def param_text(param)
        case param.kind
        when :required, nil
          param.name.to_s
        when :optional
          "#{param.name} = nil"
        when :keyword
          "#{param.name}:"
        when :rest
          "*#{param.name}"
        when :block
          param.name ? "&#{param.name}" : "&block"
        else
          param.name.to_s
        end
      end
    end
  end
end
