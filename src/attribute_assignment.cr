# ActiveModel::AttributeAssignment — strict mass assignment (unknown
# attributes raise UnknownAttributeError, same as the gem — pinned by
# oracle cases model_unknown_kwarg/model_unknown_assign).
#
# Deviation: requires the Attributes API; Ruby assigns to arbitrary
# attr_accessor writers via runtime introspection.
module ActiveModel
  module AttributeAssignment
    # Fallback sanitize: hash passes through. ForbiddenAttributesProtection
    # overrides with the raising variant.
    def __sanitize(attrs)
      attrs
    end

    def assign_attributes(attrs) : Nil
      sanitized = __sanitize(attrs)
      sanitized.each do |k, v|
        key = k.to_s
        raise UnknownAttributeError.new(key) unless __attribute?(key)
        __write_attribute(key, v)
      end
    end
  end
end
