# ActiveModel::Conversion — to_key/to_param/to_model/to_partial_path.
# The gem assumes the host responds to `persisted?` and `id`; the port
# provides nil/false defaults that hosts override.
module ActiveModel
  module Conversion
    # Override in host (implicit contract in the gem).
    def id : Value
      nil
    end

    # Override in host (implicit contract in the gem).
    def persisted? : Bool
      false
    end

    def to_key : Array(Value)?
      return nil unless persisted?
      key = Array(Value).new
      key << id
      key
    end

    def to_param : String?
      return nil unless persisted?
      to_key.try(&.map(&.to_s).join("-"))
    end

    def to_model : self
      self
    end

    # Gem 8.1: "#{model_name.collection}/#{model_name.element}" (no
    # underscore prefix — unlike ActionView's partial convention).
    def to_partial_path : String
      mn = self.class.model_name
      "#{mn.collection}/#{mn.element}"
    end

    def model_name : ActiveModel::Name
      self.class.model_name
    end
  end
end
