# ActiveModel::ForbiddenAttributesProtection — mass-assignment guard for
# strong-params-like objects. Params-like classes include
# MassAssignmentParameters; unpermitted ones make assign_attributes raise
# ForbiddenAttributesError (same class as the gem — oracle forbidden_raise).
module ActiveModel
  module MassAssignmentParameters
    abstract def to_h

    def permitted? : Bool
      true
    end
  end

  module ForbiddenAttributesProtection
    def __sanitize(attrs : Hash)
      attrs
    end

    def __sanitize(attrs : MassAssignmentParameters)
      raise ForbiddenAttributesError.new unless attrs.permitted?
      attrs.to_h
    end
  end
end
