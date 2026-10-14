# ActiveModel::Access — slice/values_at (public-send based in Ruby; the
# port reads the attributes hash — Crystal has no runtime method
# dispatch, and macros from included modules are not resolvable at
# external call sites).
module ActiveModel
  module Access
    def slice(*names : String | Symbol) : Hash(String, ActiveModel::Value)
      result = Hash(String, ActiveModel::Value).new
      names.each do |n|
        key = n.to_s
        result[key] = attributes[key] if attributes.has_key?(key)
      end
      result
    end

    def values_at(*names : String | Symbol) : Array(ActiveModel::Value)
      result = Array(ActiveModel::Value).new
      names.each { |n| result << attributes[n.to_s] }
      result
    end
  end
end
