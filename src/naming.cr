# ActiveModel::Naming — model_name mirrors the gem's ActiveModel::Name.
# The class-level `self.model_name` is planted by API/Model's
# `macro included` hook (macro finished does NOT run for including
# classes in Crystal 1.21 — see PLAN.md).
module ActiveModel
  module Naming
  end

  struct Name
    getter name : String

    def initialize(@name : String)
    end

    # underscore("Person") → "person"; keeps namespace path.
    def singular : String
      ActiveSupport::Inflector.underscore(@name)
    end

    def param_key : String
      ActiveSupport::Inflector.underscore(demodulized)
    end

    def route_key : String
      s = singular
      p = ActiveSupport::Inflector.pluralize(s)
      # Uncountable models route to "#{plural}_index" (Series → series_index).
      p == s ? "#{p}_index" : p
    end

    def singular_route_key : String
      singular
    end

    def i18n_key : String
      singular
    end

    def element : String
      ActiveSupport::Inflector.underscore(demodulized)
    end

    def collection : String
      ActiveSupport::Inflector.pluralize(element)
    end

    def human : String
      element.split("_").map(&.capitalize).join(" ")
    end

    private def demodulized : String
      @name.split("::").last
    end
  end
end
