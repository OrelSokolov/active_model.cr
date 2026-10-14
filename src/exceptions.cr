# Exceptions mirrored from the gem (class names are part of the oracle
# contract: expected.yml pins `raise:ActiveModel::...` strings).
module ActiveModel
  class Error < Exception
  end

  class UnknownAttributeError < Error
    def initialize(attribute : String)
      super("unknown attribute '#{attribute}'")
    end
  end

  class StrictValidationFailed < Error
  end

  class ValidationError < Error
  end

  class ForbiddenAttributesError < Error
    def initialize(message = "Can't copy unpermitted params")
      super(message)
    end
  end
end
