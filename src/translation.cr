# ActiveModel::Translation — human_attribute_name with the gem's
# humanize fallback ("first_name" → "First name"). The class-level
# variant is planted by API/Model's `macro included` hook (see
# naming.cr for why not macro finished).
module ActiveModel
  module Translation
    def human_attribute_name(attribute : String | Symbol) : String
      ActiveModel.humanize_attribute(attribute.to_s)
    end
  end

  # "first_name" → "First name", "m" → "M", "a.b" → "A b" (dots split too,
  # for nested errors — same as the AR port).
  def self.humanize_attribute(name : String) : String
    parts = name.gsub(".", "_").split("_")
    parts.map_with_index { |p, i| i == 0 ? p.capitalize : p }.join(" ")
  end
end
