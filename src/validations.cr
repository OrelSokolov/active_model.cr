# ActiveModel::Validations — DSL ported from active_record.cr/validations.cr
# (generalized out of AR), messages 1:1 with activemodel 8.1.4 (verified
# against oracle/expected.yml).
#
# Deviations (same family as AR.cr):
# - `if:`/`unless:` are Ruby keywords in kwargs position — use
#   `condition:`/`unless_condition:` with a method-name Symbol.
# - Custom EachValidators resolve through a compile-time registry
#   (`ActiveModel::Validations.register_validator "upcase",
#   UpcaseValidator`) — Ruby resolves `UpcaseValidator` via runtime
#   const-get. Unknown validators raise ArgumentError at runtime, matching
#   the gem's class-definition-time raise (oracle val_unknown_validator).
module ActiveModel
  module Validations
    @__errors = Errors.new

    def errors : Errors
      @__errors
    end

    def valid?(context : Symbol? = nil) : Bool
      @__errors.clear
      __run_validations(context)
      if strict_error = @__errors.find(&.strict?)
        raise StrictValidationFailed.new(
          "#{ActiveModel.humanize_attribute(strict_error.attribute)} #{strict_error.message}")
      end
      @__errors.empty?
    end

    def invalid?(context : Symbol? = nil) : Bool
      !valid?(context)
    end

    def __validation_on?(context : Symbol, on : Symbol | Array(Symbol)) : Bool
      on.is_a?(Array) ? on.includes?(context) : on == context
    end

    # Numeric coercion for numericality: String "4.5" IS a number (gem
    # parses strings), true/nil are not.
    def __to_number(value : Value) : Float64?
      case value
      when Int32   then value.to_f64
      when Int64   then value.to_f64
      when Float64 then value
      when String  then value.to_f64?
      else              nil
      end
    end

    def __integer_value?(value : Value) : Bool
      case value
      when Int32, Int64 then true
      when Float64      then value == value.trunc
      when String
        f = value.to_f64?
        !f.nil? && f == f.trunc
      else
        false
      end
    end

    # Base dispatcher planted on first DSL use (macro finished does NOT
    # run for including classes in Crystal 1.21 — see PLAN.md; each DSL
    # call chains onto the previous definition via previous_def).
    macro __plant_validation_base
      def __run_validations(context : Symbol?) : Nil
      end
    end

    # --- DSL -------------------------------------------------------------
    # validates :title, presence: true, length: {minimum: 2, maximum: 5}
    # validates :age, numericality: {only_integer: true, greater_than: 5}
    # validates :email, format: {with: /.../}, inclusion: {in: [...]},
    #   exclusion: {in: [...]}, acceptance: true, confirmation: true
    #   ... on: :update, strict: true, condition: :method, unless_condition: :method
    # Custom validators: any other kwarg → registry lookup by name.
    macro validates(*columns, presence = nil, absence = nil, length = nil,
                    numericality = nil, format = nil, inclusion = nil,
                    exclusion = nil, acceptance = nil, confirmation = nil,
                    on = nil, strict = false, allow_nil = false,
                    allow_blank = false, condition = nil,
                    unless_condition = nil, **other)
      {% for col in columns %}
        {% n = @type.methods.select { |m| m.name.stringify.starts_with?("validation__") }.size %}
        {% cname = col.id %}
        {% unless @type.methods.any? { |m| m.name.stringify == "__run_validations" } %}
          __plant_validation_base
        {% end %}
        {% if confirmation %}
          # Confirmation slot rides the attribute registry (identity cast)
          # so mass assignment accepts it — mirrors the gem's generated
          # attr_accessor for <attr>_confirmation. Dispatch is appended
          # to the attribute previous_def chains.
          {% unless @type.methods.any? { |m| m.name.stringify == "__attribute?" } %}
            __plant_attribute_bases
          {% end %}

          def __attribute_names : Array(String)
            previous_def + [{{cname.stringify}} + "_confirmation"]
          end

          def __attribute?(key : String) : Bool
            key == {{cname.stringify}} + "_confirmation" ? true : previous_def
          end

          def __write_attribute(key : String, v : ActiveModel::Value) : Nil
            if key == {{cname.stringify}} + "_confirmation"
              @__attributes[key] = v
            else
              previous_def
            end
          end

          def {{cname}}_confirmation : ActiveModel::Value
            __read_attribute({{cname.stringify}} + "_confirmation")
          end

          def {{cname}}_confirmation=(value : ActiveModel::Value)
            __write_attribute({{cname.stringify}} + "_confirmation", value)
          end
        {% end %}

        def validation__{{cname}}__{{n}}(context : Symbol?) : Nil
          {% if on %}
            return unless context && __validation_on?(context, {{on}})
          {% end %}
          {% if condition %}
            return unless {{condition.id}}
          {% end %}
          {% if unless_condition %}
            return if {{unless_condition.id}}
          {% end %}
          value = __read_attribute({{col.id.stringify}})
          {% if allow_nil %}
            return if value.nil?
          {% end %}
          {% if allow_blank %}
            return if value.nil? || (value.is_a?(String) && value.strip.empty?)
          {% end %}

          {% if presence %}
            if value.nil? || (value.is_a?(String) && value.strip.empty?)
              errors.add({{col}},"can't be blank", :blank, strict: {{strict}})
            end
          {% end %}

          {% if absence %}
            unless value.nil? || (value.is_a?(String) && value.strip.empty?)
              errors.add({{col}},"must be blank", :present, strict: {{strict}})
            end
          {% end %}

          {% if length %}
            {% max = length[:maximum] %}
            {% min = length[:minimum] %}
            {% if max %}
              if value.is_a?(String) && value.size > {{max}}
                errors.add({{col}},"is too long (maximum is {{max}} characters)", :too_long, strict: {{strict}})
              end
            {% end %}
            {% if min %}
              if value.is_a?(String) && value.size < {{min}}
                errors.add({{col}},"is too short (minimum is {{min}} characters)", :too_short, strict: {{strict}})
              end
            {% end %}
          {% end %}

          {% if numericality %}
            {% gt = nil %}{% gte = nil %}{% lt = nil %}{% lte = nil %}{% only_int = nil %}
            {% if numericality.is_a?(NamedTupleLiteral) %}
              {% gt = numericality[:greater_than] %}
              {% gte = numericality[:greater_than_or_equal_to] %}
              {% lt = numericality[:less_than] %}
              {% lte = numericality[:less_than_or_equal_to] %}
              {% only_int = numericality[:only_integer] %}
            {% end %}
            num = __to_number(value)
            if num.nil?
              errors.add({{col}},"is not a number", :not_a_number, strict: {{strict}})
            else
              {% if only_int %}
                unless __integer_value?(value)
                  errors.add({{col}},"must be an integer", :not_an_integer, strict: {{strict}})
                end
              {% end %}
              {% if gt %}
                errors.add({{col}},"must be greater than {{gt}}", :greater_than, strict: {{strict}}) if num <= {{gt}}.to_f
              {% end %}
              {% if gte %}
                errors.add({{col}},"must be greater than or equal to {{gte}}", :greater_than_or_equal_to, strict: {{strict}}) if num < {{gte}}.to_f
              {% end %}
              {% if lt %}
                errors.add({{col}},"must be less than {{lt}}", :less_than, strict: {{strict}}) if num >= {{lt}}.to_f
              {% end %}
              {% if lte %}
                errors.add({{col}},"must be less than or equal to {{lte}}", :less_than_or_equal_to, strict: {{strict}}) if num > {{lte}}.to_f
              {% end %}
            end
          {% end %}

          {% if format %}
            {% pattern = format[:with] %}
            unless value.is_a?(String) && value.match({{pattern}})
              errors.add({{col}},"is invalid", :invalid, strict: {{strict}})
            end
          {% end %}

          {% if inclusion %}
            {% in_list = inclusion[:in] %}
            unless value.nil? || ({{in_list}}).map(&.to_s).includes?(value.to_s)
              errors.add({{col}},"is not included in the list", :inclusion, strict: {{strict}}, detail_value: value)
            end
          {% end %}

          {% if exclusion %}
            {% ex_list = exclusion[:in] %}
            unless value.nil? || !({{ex_list}}).map(&.to_s).includes?(value.to_s)
              errors.add({{col}},"is reserved", :exclusion, strict: {{strict}})
            end
          {% end %}

          {% if acceptance %}
            # Rails 8: acceptance skips nil values (only present-but-not
            # accepted fails).
            unless value.nil? || value == true || value == "1"
              errors.add({{col}},"must be accepted", :accepted, strict: {{strict}})
            end
          {% end %}

          {% if confirmation %}
            if (conf = __read_attribute({{cname.stringify}} + "_confirmation")) && conf != value
              errors.add(:"{{cname}}_confirmation", "doesn't match {{col.id.stringify.capitalize.id}}", :confirmation, strict: {{strict}})
            end
          {% end %}

          {% for key, val in other %}
            ActiveModel::Validations.validator_for({{key.stringify}}).new({{val}}).validate_each(self, {{col.id.stringify}}, value)
          {% end %}
          nil
        end

        # Declaration order = run order: previous_def first, then this
        # validation.
        def __run_validations(context : Symbol?) : Nil
          previous_def
          validation__{{cname}}__{{n}}(context)
        end
      {% end %}
    end

    # validates! — strict version (raises StrictValidationFailed on
    # invalid? — oracle val_strict_raise).
    macro validates!(*columns, **opts)
      validates({{columns.splat}}, strict: true, {% for k, v in opts %} {{k}}: {{v}}, {% end %})
    end

    # Custom validations: `validate :check_name` or `validate do ... end`.
    macro validate(method_name = nil, &block)
      {% unless @type.methods.any? { |m| m.name.stringify == "__run_validations" } %}
        __plant_validation_base
      {% end %}
      {% n = @type.methods.select { |m| m.name.stringify.starts_with?("validation__") }.size %}
      {% if method_name %}
        def validation__custom__{{n}}(context : Symbol?) : Nil
          {{method_name.id}}
          nil
        end
      {% else %}
        def validation__custom__{{n}}(context : Symbol?) : Nil
          {{block.body}}
          nil
        end
      {% end %}

      def __run_validations(context : Symbol?) : Nil
        previous_def
        validation__custom__{{n}}(context)
      end
    end

    # --- EachValidator registry -------------------------------------------
    @@validator_registry = Hash(String, EachValidator.class).new

    def self.register_validator(key : String, klass : EachValidator.class) : Nil
      @@validator_registry[key] = klass
    end

    def self.validator_for(key : String) : EachValidator.class
      @@validator_registry[key]? || raise ArgumentError.new("Unknown validator: #{key}")
    end
  end

  # Base for custom `validates :x, upcase: true` validators. Register:
  #   class UpcaseValidator < ActiveModel::EachValidator ... end
  #   ActiveModel::Validations.register_validator("upcase", UpcaseValidator)
  class EachValidator
    def initialize(@options : Value)
    end

    def validate_each(record : ActiveModel::Validations, attribute : String, value : Value) : Nil
    end
  end
end
