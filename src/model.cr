# ActiveModel::API + ActiveModel::Model.
#
# Gem 8.1: API = the full model interface (Naming, Translation, Conversion,
# Validations, AttributeAssignment, Callbacks-able); Model = API + Access.
# Port addition: Attributes is included in API — Crystal needs a typed
# attribute set for runtime reads (Ruby uses attr_accessor + reflection).
#
# `macro included` plants the class-level interface (self.model_name,
# self.human_attribute_name) and the dispatch bases (empty
# __run_validations / attribute dispatchers) so DSL-less models work.
# Nested includes do not re-fire hooks: API's hook covers Model and
# direct API includers, Model's hook covers plain models (Person).
module ActiveModel
  module API
    macro included
      def self.model_name : ActiveModel::Name
        ActiveModel::Name.new({{ @type.name.stringify }})
      end

      def self.human_attribute_name(attribute : String | Symbol) : String
        ActiveModel.humanize_attribute(attribute.to_s)
      end

      {% unless @type.methods.any? { |m| m.name.stringify == "__attribute?" } %}
        __plant_attribute_bases
      {% end %}

      {% unless @type.methods.any? { |m| m.name.stringify == "__run_validations" } %}
        __plant_validation_base
      {% end %}
    end

    include ActiveModel::Naming
    include ActiveModel::Translation
    include ActiveModel::Conversion
    include ActiveModel::Attributes
    include ActiveModel::AttributeAssignment
    include ActiveModel::Validations

    def initialize(**attrs)
      assign_attributes(attrs.to_h)
    end
  end

  module Model
    macro included
      def self.model_name : ActiveModel::Name
        ActiveModel::Name.new({{ @type.name.stringify }})
      end

      def self.human_attribute_name(attribute : String | Symbol) : String
        ActiveModel.humanize_attribute(attribute.to_s)
      end

      {% unless @type.methods.any? { |m| m.name.stringify == "__attribute?" } %}
        __plant_attribute_bases
      {% end %}

      {% unless @type.methods.any? { |m| m.name.stringify == "__run_validations" } %}
        __plant_validation_base
      {% end %}
    end

    include ActiveModel::API
    include ActiveModel::Access

    # Crystal's `new` does not pick up initialize from indirectly included
    # modules (API's copy is invisible through Model) — redefined here.
    def initialize(**attrs)
      assign_attributes(attrs.to_h)
    end
  end
end
