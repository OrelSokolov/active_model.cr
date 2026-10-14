# ActiveModel::Type — cast semantics 1:1 with activemodel 8.1.4
# (verified against oracle/expected.yml: "abc"→0 for Integer, ""→nil for
# Boolean, nil→nil for String — NOT "").
module ActiveModel
  module Type
    abstract class Base
      def cast(value : Value) : Value
        value
      end
    end

    # Ruby: `case value when true then 1 when false then 0 else value.to_i end`
    # — String#to_i semantics ("abc" → 0, "42" → 42); Float truncates.
    class Integer < Base
      def cast(value : Value) : Value
        case value
        when Nil         then nil
        when Int32       then value.to_i64
        when Int64       then value
        when Float64     then value.to_i64
        when Bool        then value ? 1_i64 : 0_i64
        when ::String     then value.to_i64? || 0_i64
        when Array, Hash then value.to_s.to_i64? || 0_i64
        else                  value.to_s.to_i64? || 0_i64
        end
      end
    end

    class Float < Base
      def cast(value : Value) : Value
        case value
        when Nil     then nil
        when Int32   then value.to_f64
        when Int64   then value.to_f64
        when Float64 then value
        when Bool    then value ? 1.0 : 0.0
        when ::String then value.to_f64? || 0.0
        else              value.to_s.to_f64? || 0.0
        end
      end
    end

    # Ruby: nil→nil; ""→nil; false/0/"0"/"false"/"off"/"f"→false; else true.
    class Boolean < Base
      def cast(value : Value) : Value
        case value
        when Nil     then nil
        when Bool    then value
        when Int32   then value != 0
        when Int64   then value != 0
        when ::String
          case value
          when ""            then nil
          when "0", "false", "off", "f" then false
          else                    true
          end
        else
          true
        end
      end
    end

    # Ruby: nil→nil (quirk pinned by oracle type_string_nil), else to_s.
    class String < Base
      def cast(value : Value) : Value
        return nil if value.nil?
        value.to_s
      end
    end

    @@registry = Hash(::String, Base.class).new
    @@registry["integer"] = Integer
    @@registry["float"] = Float
    @@registry["string"] = String
    @@registry["boolean"] = Boolean

    def self.lookup(type : Symbol | String) : Base.class
      key = type.to_s
      @@registry[key]? || raise ArgumentError.new("Unknown type: #{key}")
    end

    def self.register(key : String, type : Base.class) : Nil
      @@registry[key] = type
    end
  end
end
