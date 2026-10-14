# ActiveModel::Attributes — the typed attribute set (the port's storage
# layer; Ruby models use attr_accessor + runtime introspection, which
# Crystal does not have — `attribute` is the AM-native DSL for both).
#
# Dispatch is built as previous_def chains in the class body: each
# `attribute` call redefines __attribute_names/__attribute?/
# __write_attribute/__attribute_default chaining onto the previous
# definition (first-use guard plants the base methods — macro finished
# does NOT run for including classes in Crystal 1.21, see PLAN.md).
module ActiveModel
  module Attributes
    @__attributes = Hash(String, Value).new

    # Base dispatchers, planted into the class on first `attribute` use
    # (also planted by Model/API's included hook).
    macro __plant_attribute_bases
      def __attribute_names : Array(String)
        [] of String
      end

      def __attribute?(key : String) : Bool
        false
      end

      def __write_attribute(key : String, v : ActiveModel::Value) : Nil
      end

      def __attribute_default(key : String) : ActiveModel::Value
        nil
      end
    end

    # type: :integer/:string/:boolean/:float; nil = untyped (identity
    # cast — mirrors plain attr_accessor semantics).
    macro attribute(name, type = nil, default = nil)
      {% unless @type.methods.any? { |m| m.name.stringify == "__attribute?" } %}
        __plant_attribute_bases
      {% end %}

      def {{name.id}} : ActiveModel::Value
        __read_attribute({{name.id.stringify}})
      end

      def {{name.id}}=(v : ActiveModel::Value)
        __write_attribute({{name.id.stringify}}, v)
      end

      def __attribute_names : Array(String)
        previous_def + [{{name.id.stringify}}]
      end

      def __attribute?(key : String) : Bool
        key == {{name.id.stringify}} ? true : previous_def
      end

      def __write_attribute(key : String, v : ActiveModel::Value) : Nil
        if key == {{name.id.stringify}}
          {% if type %}
            val = ActiveModel::Type::{{ type.id.stringify.capitalize.id }}.new.cast(v)
          {% else %}
            val = v
          {% end %}
          # Dirty tracking must ride the chain: class-body defs shadow
          # module methods, so Dirty cannot wrap __write_attribute.
          {% if @type.ancestors.any? { |a| a.stringify.starts_with?("ActiveModel::Dirty") } %}
            __dirty_track_write(key, val)
          {% else %}
            @__attributes[key] = val
          {% end %}
        else
          previous_def
        end
      end

      {% if default != nil %}
        def __attribute_default(key : String) : ActiveModel::Value
          key == {{name.id.stringify}} ? {{ default }} : previous_def
        end
      {% end %}

      # Dirty per-attribute queries — only when Dirty is included.
      {% if @type.ancestors.any? { |a| a.stringify.starts_with?("ActiveModel::Dirty") } %}
        def {{name.id}}_was : ActiveModel::Value
          if @__changed_attributes.has_key?({{name.id.stringify}})
            @__changed_attributes[{{name.id.stringify}}]
          else
            __read_attribute({{name.id.stringify}})
          end
        end

        def {{name.id}}_changed? : Bool
          @__changed_attributes.has_key?({{name.id.stringify}})
        end

        def {{name.id}}_change : Array(ActiveModel::Value)?
          changes[{{name.id.stringify}}]?
        end

        def {{name.id}}_previously_changed? : Bool
          @__previous_changes.has_key?({{name.id.stringify}})
        end

        def {{name.id}}_previous_change : Array(ActiveModel::Value)?
          @__previous_changes[{{name.id.stringify}}]?
        end
      {% end %}
    end

    def __read_attribute(key : String) : ActiveModel::Value
      if @__attributes.has_key?(key)
        @__attributes[key]
      else
        __attribute_default(key)
      end
    end

    def attributes : Hash(String, ActiveModel::Value)
      hash = Hash(String, ActiveModel::Value).new
      __attribute_names.each { |n| hash[n] = __read_attribute(n) }
      hash
    end
  end
end
