# ActiveModel::Serialization + Serializers::JSON.
#
# as_json/serializable_hash read the typed attribute set; only/except
# filter attributes. The `methods:` option needs runtime method dispatch
# in Ruby — the port requires the callable methods to be declared up
# front with `serialize_method :shout` (compile-time dispatch table).
#
# from_json goes through mass assignment: untyped attributes keep raw
# JSON scalars ("5" stays String — quirk pinned by oracle
# ser_from_json_types), typed attributes cast (ser_from_json_typed).
module ActiveModel
  module Serialization
    # Compile-time dispatch table: each call chains onto the previous
    # definition via previous_def (first-use guard plants the raising
    # base — macro finished does not run for including classes).
    macro serialize_method(*names)
      {% unless @type.methods.any? { |m| m.name.stringify == "__serializable_extra" } %}
        def __serializable_extra(name : String) : ActiveModel::Value
          raise ArgumentError.new("Undeclared serializable method: #{name}")
        end
      {% end %}
      {% for n in names %}
        def __serializable_extra(name : String) : ActiveModel::Value
          if name == {{n.id.stringify}}
            {{n.id}}
          else
            previous_def
          end
        end
      {% end %}
    end

    def serializable_hash(**options) : Hash(String, ActiveModel::Value)
      only = options[:only]?.try(&.map(&.to_s))
      except = options[:except]?.try(&.map(&.to_s))
      methods = options[:methods]?.try(&.map(&.to_s))
      result = Hash(String, ActiveModel::Value).new
      attributes.each do |k, v|
        next if only && !only.includes?(k)
        next if except && except.includes?(k)
        result[k] = v
      end
      methods.try &.each { |m| result[m] = __serializable_extra(m) }
      result
    end

    def as_json(**options) : Hash(String, ActiveModel::Value)
      serializable_hash(**options)
    end
  end

  module Serializers
    module JSON
      include ActiveModel::Serialization

      def from_json(json : String) : Nil
        hash = ::JSON.parse(json).as_h
        converted = Hash(String, ActiveModel::Value).new
        hash.each { |k, v| converted[k] = __any_to_value(v) }
        assign_attributes(converted)
      end

      def to_json : String
        as_json.to_json
      end

      private def __any_to_value(v : ::JSON::Any) : ActiveModel::Value
        case raw = v.raw
        when Nil, Bool, Int64, Float64, String then raw
        when Int32                              then raw
        else                                         raw.to_s
        end
      end
    end
  end
end
