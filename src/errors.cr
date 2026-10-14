# ActiveModel::Errors — port of the gem's lazy Errors (8.1 shape): a list
# of Error records with attribute + type (Symbol) + rendered message.
# `details`/`attribute_names`/`as_json` use Symbol keys — Crystal has no
# runtime String→Symbol, so Error keeps the Symbol form alongside the
# String form (the gem's attribute is whatever was passed to add;
# string-added errors simply don't appear in the symbol-keyed views).
# Entries hold only :error (+ :value when set) — the `message:` override
# is NOT part of details (quirk pinned by oracle err_details).
module ActiveModel
  class Errors
    struct Error
      getter attribute : String
      getter attribute_sym : Symbol?
      getter type : Symbol
      getter message : String?
      getter? strict : Bool
      getter detail_value : Value?

      def initialize(@attribute : String, @type : Symbol, @message : String? = nil,
                     @strict : Bool = false, @detail_value : Value? = nil,
                     @attribute_sym : Symbol? = nil)
      end
    end

    alias DetailValue = Symbol | Value

    include Enumerable(Error)

    @errors = [] of Error

    def initialize
    end

    def add(attribute : String | Symbol, message : String, type : Symbol = :invalid,
            strict : Bool = false, detail_value : Value? = nil) : Nil
      @errors << Error.new(attribute.to_s, type, message, strict, detail_value,
        attribute.is_a?(Symbol) ? attribute : nil)
    end

    def add(attribute : String | Symbol, type : Symbol, detail_value : Value? = nil) : Nil
      @errors << Error.new(attribute.to_s, type, default_message(type),
        detail_value: detail_value,
        attribute_sym: attribute.is_a?(Symbol) ? attribute : nil)
    end

    def <<(error : Error) : Nil
      @errors << error
    end

    def clear : Nil
      @errors.clear
    end

    def empty? : Bool
      @errors.empty?
    end

    def size : Int32
      @errors.size
    end

    def count : Int32
      @errors.size
    end

    def each(& : Error ->) : Nil
      @errors.each { |e| yield e }
    end

    # errors[:name] → message strings for the attribute.
    def [](attribute : String | Symbol) : Array(String)
      a = attribute.to_s
      @errors.select { |e| e.attribute == a }.map { |e| e.message.not_nil! }
    end

    def messages : Array(String)
      @errors.map { |e| e.message.not_nil! }
    end

    def where(attribute : String | Symbol) : Array(Error)
      a = attribute.to_s
      @errors.select { |e| e.attribute == a }
    end

    def where(attribute : String | Symbol, type : Symbol) : Array(Error)
      a = attribute.to_s
      @errors.select { |e| e.attribute == a && e.type == type }
    end

    def added?(attribute : String | Symbol, type : Symbol) : Bool
      a = attribute.to_s
      @errors.any? { |e| e.attribute == a && e.type == type }
    end

    def include?(attribute : String | Symbol) : Bool
      a = attribute.to_s
      @errors.any? { |e| e.attribute == a }
    end

    def delete(attribute : String | Symbol) : Array(Error)
      a = attribute.to_s
      removed = @errors.select { |e| e.attribute == a }
      @errors.reject! { |e| e.attribute == a }
      removed
    end

    def details : Hash(Symbol, Array(Hash(Symbol, DetailValue)))
      result = Hash(Symbol, Array(Hash(Symbol, DetailValue))).new
      @errors.each do |e|
        sym = e.attribute_sym
        next unless sym
        entry = Hash(Symbol, DetailValue).new
        entry[:error] = e.type
        entry[:value] = e.detail_value if e.detail_value
        (result[sym] ||= [] of Hash(Symbol, DetailValue)) << entry
      end
      result
    end

    def group_by_attribute : Hash(String, Array(Error))
      result = Hash(String, Array(Error)).new
      @errors.each do |e|
        (result[e.attribute] ||= [] of Error) << e
      end
      result
    end

    def attribute_names : Array(Symbol)
      names = [] of Symbol
      @errors.each do |e|
        sym = e.attribute_sym
        next unless sym
        names << sym unless names.includes?(sym)
      end
      names
    end

    def as_json : Hash(Symbol, Array(String))
      result = Hash(Symbol, Array(String)).new
      @errors.each do |e|
        sym = e.attribute_sym
        next unless sym
        (result[sym] ||= [] of String) << e.message.not_nil!
      end
      result
    end

    def full_messages : Array(String)
      @errors.map { |e| full_message(e) }
    end

    def full_messages_for(attribute : String | Symbol) : Array(String)
      a = attribute.to_s
      @errors.select { |e| e.attribute == a }.map { |e| full_message(e) }
    end

    private def full_message(e : Error) : String
      "#{ActiveModel.humanize_attribute(e.attribute)} #{e.message || default_message(e.type)}"
    end

    private def default_message(type : Symbol) : String
      case type
      when :blank           then "can't be blank"
      when :too_long        then "is too long"
      when :too_short       then "is too short"
      when :not_a_number    then "is not a number"
      when :not_an_integer  then "must be an integer"
      when :greater_than    then "must be greater than"
      when :invalid         then "is invalid"
      else                       "is invalid"
      end
    end
  end
end
