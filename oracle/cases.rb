# Synthetic oracle cases for ActiveModel P0 (Iteration 0).
#
# Run against the ORIGINAL gem:
#   ruby oracle/cases.rb > oracle/expected.yml
#
# Each line: "<case_id>\t<rendered result>". The same case IDs are
# mirrored 1:1 in spec/oracle_spec.cr; the Crystal port must reproduce
# expected.yml exactly (both implementations pass the same expectations,
# captured from activemodel 8.1.4, ruby 3.4.5). Reference minitest suites
# from rails/rails v8.1.4 live in oracle/rails-tests/ (gem ships lib only).
#
# API quirks verified by probe.rb (deleted):
# - AM::Dirty needs AM::Attributes for `attribute`; `*_in_database` is
#   AR-only in 8.1.4, absent on plain AM.
# - SecurePassword needs the host class to define `password_digest`.
# - Access provides #slice/#values_at (public_send-based), not #[].
# - sanitize_for_mass_assignment is private (used by assign_attributes).
# - from_json needs Model (attribute assignment) + Serializers::JSON.
require "active_model"
require "active_model/serializers/json"

def render(v)
  case v
  when true, false, Integer, Float, String then v.inspect
  when Symbol then ":#{v}"
  when nil then "nil"
  when Array then "A[#{v.map { |e| render(e) }.join(',')}]"
  when Hash then "H{#{v.sort_by { |k, _| k.to_s }.map { |k, val| "#{render(k)}=>#{render(val)}" }.join(',')}}"
  when Class, Module then v.name
  when Exception then "raise:#{v.class.name}"
  else v.to_s.inspect
  end
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

# --- test models ---------------------------------------------------

class Person
  include ActiveModel::Model
  attr_accessor :name, :age, :first_name
  validates :name, presence: true
end

class ApiModel
  include ActiveModel::API
  attr_accessor :email
  validates :email, presence: true
end

class Rec
  # Conversion contract: id + persisted?
  include ActiveModel::Conversion
  attr_accessor :id
  def initialize(id)
    @id = id
  end
  def persisted?
    id ? true : false
  end
end

class Series
  include ActiveModel::Model
end

class StrictP
  include ActiveModel::Model
  attr_accessor :name
  validates! :name, presence: true
end

class VModel
  include ActiveModel::Model
  attr_accessor :a, :b, :c, :d, :a_confirmation, :terms, :state
  validates :a, presence: true
  validates :b, absence: true
  validates :c, length: { minimum: 2, maximum: 5 }
  validates :d, format: { with: /\A\d+\z/ }
  validates :a, confirmation: true
  validates :terms, acceptance: true
  validates :state, inclusion: { in: %w[open closed] }
end

class NModel
  include ActiveModel::Model
  attr_accessor :n, :m
  validates :n, numericality: true
  validates :m, numericality: { only_integer: true, greater_than: 5, less_than_or_equal_to: 10 }
end

class CtxModel
  include ActiveModel::Model
  attr_accessor :x, :y
  validates :x, presence: true, on: :create
  validates :y, presence: true, on: :update
end

class CondModel
  include ActiveModel::Model
  attr_accessor :a, :b
  validates :a, presence: true, if: -> { b }
end

class UpcaseValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    record.errors.add(attribute, :invalid, message: "not upcase") unless value == value.to_s.upcase
  end
end

class CustModel
  include ActiveModel::Model
  attr_accessor :code
  validates :code, upcase: true
  validate :must_start_with_z

  def must_start_with_z
    errors.add(:code, "must start with Z") unless code.to_s.start_with?("Z")
  end
end

class DirtyModel
  include ActiveModel::Attributes
  include ActiveModel::Dirty
  attribute :name, :string
end

class UserP
  include ActiveModel::SecurePassword
  attr_accessor :password_digest
  has_secure_password
end

class Prot
  include ActiveModel::ForbiddenAttributesProtection
  include ActiveModel::AttributeAssignment
  attr_accessor :name
end

class Acc
  include ActiveModel::Access
  def initialize(n)
    @n = n
  end
  def name
    @n
  end
  def attributes
    {"name" => @n}
  end
end

class Ser
  include ActiveModel::Model
  include ActiveModel::Serializers::JSON
  attr_accessor :name, :age
  def attributes
    {"name" => nil, "age" => nil}
  end
  def shout
    "#{name}!"
  end
end

class Attrs
  include ActiveModel::Attributes
  attribute :age, :integer, default: 7
  attribute :note, :string
end

class TypedSer
  # Typed path: casting lives in the attribute layer (AM::Type), not in
  # from_json itself — the writer is type-aware, mass assignment casts.
  include ActiveModel::AttributeAssignment
  include ActiveModel::Attributes
  include ActiveModel::Serializers::JSON
  attribute :age, :integer
end

class Cb
  extend ActiveModel::Callbacks
  define_callbacks :save
  set_callback :save, :before, :mark_before
  set_callback :save, :after, :mark_after
  set_callback :save, :around do |o, block|
    o.log << :around_in
    block.call
    o.log << :around_out
  end
  attr_accessor :log
  def initialize
    @log = []
  end
  def mark_before
    @log << :before
  end
  def mark_after
    @log << :after
  end
  def run
    run_callbacks(:save) { @log << :yield }
  end
end

class CbAbort
  extend ActiveModel::Callbacks
  define_callbacks :save, terminator: ->(_target, result) { result == false }
  set_callback :save, :before do |o|
    o.log << :stopped
    throw :abort
  end
  attr_accessor :log
  def initialize
    @log = []
  end
  def run
    run_callbacks(:save) { @log << :yield }
  end
end

# --- Naming / Translation ------------------------------------------

case_run("naming_param_key")        { Person.model_name.param_key }
case_run("naming_route_key")        { Person.model_name.route_key }
case_run("naming_singular_route")   { Person.model_name.singular_route_key }
case_run("naming_i18n_key")         { Person.model_name.i18n_key.to_s }
case_run("naming_human")            { Person.model_name.human }
case_run("naming_name")             { Person.model_name.name }
case_run("naming_uncount_route")    { Series.model_name.route_key }
case_run("naming_uncount_sroute")   { Series.model_name.singular_route_key }
case_run("translation_human_attr")  { Person.human_attribute_name(:first_name) }

# --- Conversion ------------------------------------------------------

case_run("conv_to_key_new")         { Rec.new(nil).to_key }
case_run("conv_to_param_new")       { Rec.new(nil).to_param }
case_run("conv_to_key_persisted")   { Rec.new(42).to_key }
case_run("conv_to_param_persisted") { Rec.new(42).to_param }
case_run("conv_to_model")           { r = Rec.new(1); r.to_model.equal?(r) }
case_run("api_persisted")           { ApiModel.new(email: "e").persisted? }
case_run("api_to_param")            { ApiModel.new(email: "e").to_param }
case_run("api_model_name")          { ApiModel.new(email: "e").model_name.name }
case_run("api_to_partial_path")     { ApiModel.new(email: "e").to_partial_path }

# --- Model / API / AttributeAssignment -------------------------------

case_run("model_assign")            { p = Person.new(name: "Ann", age: 3); "#{p.name}/#{p.age}" }
case_run("model_valid")             { Person.new(name: "Ann").valid? }
case_run("model_invalid")           { Person.new(age: 1).valid? }
case_run("model_invalid_msgs")      { m = Person.new(age: 1); m.valid?; m.errors.full_messages }
case_run("model_unknown_kwarg")     { Person.new(bogus: 1); "no-raise" }
case_run("model_unknown_assign")    { p = Person.new; p.assign_attributes(bogus: 1); "no-raise" }
case_run("assign_string_keys")      { p = Person.new; p.assign_attributes("name" => "Bo"); p.name }
case_run("model_name_on_instance")  { Person.new(name: "x").model_name.param_key }

# --- Validations ------------------------------------------------------

case_run("val_presence_blank")      { v = VModel.new(a: nil); v.valid?; v.errors[:a] }
case_run("val_presence_ok")         { VModel.new(a: "x").valid? }
case_run("val_absence")             { v = VModel.new(a: "x", b: "set"); v.valid?; v.errors[:b] }
case_run("val_length_short")        { v = VModel.new(a: "x", c: "a"); v.valid?; v.errors[:c] }
case_run("val_length_long")         { v = VModel.new(a: "x", c: "abcdef"); v.valid?; v.errors[:c] }
case_run("val_length_boundary_min") { VModel.new(a: "x", c: "ab", d: "1", terms: "1", state: "open", b: nil, a_confirmation: "x").valid? }
case_run("val_format_bad")          { v = VModel.new(a: "x", d: "12x"); v.valid?; v.errors[:d] }
case_run("val_confirmation_mism")   { v = VModel.new(a: "x", a_confirmation: "y"); v.valid?; v.errors[:a] }
case_run("val_acceptance_unset")    { v = VModel.new(a: "x", a_confirmation: "x"); v.valid?; v.errors[:terms] }
case_run("val_inclusion_out")       { v = VModel.new(a: "x", state: "gone"); v.valid?; v.errors[:state] }
case_run("val_numericality_str")    { v = NModel.new(n: "4.5", m: 7); v.valid?; v.errors[:n] }
case_run("val_numericality_bool")   { v = NModel.new(n: true); v.valid?; v.errors[:n] }
case_run("val_num_int_gt")          { v = NModel.new(n: 1, m: 5); v.valid?; v.errors[:m] }
case_run("val_num_int_lte")         { NModel.new(n: 1, m: 10).valid? }
case_run("val_num_int_gt_ok")       { NModel.new(n: 1, m: 6).valid? }
case_run("val_num_float_not_int")   { v = NModel.new(n: 1, m: 6.5); v.valid?; v.errors[:m] }
case_run("val_context_create_x")    { m = CtxModel.new(y: 1); m.valid?(:create); m.errors[:x] }
case_run("val_context_create_y_ok") { m = CtxModel.new(x: 1); m.valid?(:create) }
case_run("val_context_update_y")    { m = CtxModel.new(x: 1); m.valid?(:update); m.errors[:y] }
case_run("val_context_default")     { m = CtxModel.new; m.valid?; m.errors.attribute_names }
case_run("val_if_b_true")           { m = CondModel.new(b: true); m.valid?; m.errors[:a] }
case_run("val_if_b_false")          { CondModel.new(b: false).valid? }
case_run("val_custom_each")         { m = CustModel.new(code: "abc"); m.valid?; m.errors[:code] }
case_run("val_custom_method")       { m = CustModel.new(code: "QAB"); m.valid?; m.errors[:code] }
case_run("val_custom_ok")           { CustModel.new(code: "ZAB").valid? }
case_run("val_strict_raise")        { StrictP.new.valid?; "no-raise" }
case_run("val_unknown_validator")   { klass = Class.new(Person) { validates :name, bogus: true }; klass.new(name: "x").valid?; "no-raise" }

# --- Errors ------------------------------------------------------------

case_run("err_add_msgs")            { m = Person.new; m.errors.add(:name, :blank); m.errors[:name] }
case_run("err_add_custom")          { m = Person.new; m.errors.add(:name, "custom text"); m.errors[:name] }
case_run("err_details")             { m = Person.new; m.errors.add(:name, :invalid, message: "x"); m.errors.details[:name] }
case_run("err_full_messages")       { m = Person.new; m.errors.add(:name, :blank); m.errors.full_messages }
case_run("err_full_messages_for")   { m = Person.new; m.errors.add(:name, :blank); m.errors.add(:age, :not_a_number, value: "z"); m.errors.full_messages_for(:age) }
case_run("err_where")               { m = Person.new; m.errors.add(:name, :blank); m.errors.add(:name, :invalid); m.errors.where(:name, :blank).size }
case_run("err_added")               { m = Person.new; m.errors.add(:name, :blank); m.errors.added?(:name, :blank) }
case_run("err_added_false")         { m = Person.new; m.errors.added?(:name, :blank) }
case_run("err_include")             { m = Person.new; m.errors.add(:name, :blank); m.errors.include?(:name) }
case_run("err_count")               { m = Person.new; m.errors.add(:name, :blank); m.errors.add(:age, :blank); m.errors.count }
case_run("err_empty")               { Person.new.errors.empty? }
case_run("err_delete")              { m = Person.new; m.errors.add(:name, :blank); m.errors.delete(:name); m.errors.count }
case_run("err_attribute_names")     { m = Person.new; m.errors.add(:name, :blank); m.errors.add(:age, :blank); m.errors.attribute_names }
case_run("err_as_json")             { m = Person.new; m.errors.add(:name, :blank); m.errors.as_json }
case_run("err_invalid_interactive") { m = NModel.new(n: 1, m: 5); m.valid?; m.errors.full_messages_for(:m) }

# --- Dirty --------------------------------------------------------------

case_run("dirty_initial")           { d = DirtyModel.new; [d.changed?, d.changed, d.changes] }
case_run("dirty_changed")           { d = DirtyModel.new; d.name = "bob"; d.changed? }
case_run("dirty_changed_list")      { d = DirtyModel.new; d.name = "bob"; d.changed }
case_run("dirty_changes")           { d = DirtyModel.new; d.name = "bob"; d.changes }
case_run("dirty_was")               { d = DirtyModel.new; d.name = "bob"; d.name_was }
case_run("dirty_attr_changed_q")    { d = DirtyModel.new; d.name = "bob"; d.name_changed? }
case_run("dirty_attr_change")       { d = DirtyModel.new; d.name = "bob"; d.name_change }
case_run("dirty_applied")           { d = DirtyModel.new; d.name = "bob"; d.changes_applied; d.changed? }
case_run("dirty_prev_changed")      { d = DirtyModel.new; d.name = "bob"; d.changes_applied; d.name = "rob"; [d.name_previously_changed?, d.name_previous_change] }
case_run("dirty_prev_change_same")  { d = DirtyModel.new; d.name = "bob"; d.changes_applied; d.name = "bob"; d.name_previously_changed? }
case_run("dirty_restore")           { d = DirtyModel.new; d.name = "bob"; d.changes_applied; d.name = "rob"; d.restore_attributes; [d.name, d.changed?] }
case_run("dirty_same_value")        { d = DirtyModel.new; d.name = nil; d.changed? }
case_run("dirty_changed_attrs")     { d = DirtyModel.new; d.name = "bob"; d.changed_attributes.keys }

# --- Callbacks ------------------------------------------------------------

case_run("cb_order")                { Cb.new.run }
case_run("cb_abort")                { CbAbort.new.run }

# --- Serialization ----------------------------------------------------------

case_run("ser_as_json")             { Ser.new(name: "a", age: 1).as_json }
case_run("ser_as_json_methods")     { Ser.new(name: "a").as_json(methods: [:shout]) }
case_run("ser_serializable_only")   { Ser.new(name: "a", age: 2).serializable_hash(only: [:name]) }
case_run("ser_serializable_except") { Ser.new(name: "a", age: 2).serializable_hash(except: [:name]) }
case_run("ser_to_json")             { Ser.new(name: "a").to_json }
case_run("ser_from_json")           { s = Ser.new; s.from_json(%({"name":"z","age":"5"})); [s.name, s.age] }
case_run("ser_from_json_types")     { s = Ser.new; s.from_json(%({"name":"z","age":"5"})); s.age.class }
case_run("ser_from_json_typed")     { t = TypedSer.new; t.from_json(%({"age":"5"})); t.age }
case_run("ser_typed_writer")        { t = TypedSer.new; t.age = "7"; t.age }
case_run("ser_typed_assign")        { t = TypedSer.new; t.assign_attributes(age: "9"); t.age }

# --- Attributes / Type ---------------------------------------------------

case_run("attrs_default")           { Attrs.new.age }
case_run("attrs_hash")              { Attrs.new.attributes }
case_run("attrs_cast_write")        { a = Attrs.new; a.age = "9"; a.age }
case_run("attrs_string_nil")        { Attrs.new.note }
case_run("type_bool_zero")          { ActiveModel::Type::Boolean.new.cast("0") }
case_run("type_bool_one")           { ActiveModel::Type::Boolean.new.cast("1") }
case_run("type_bool_empty")         { ActiveModel::Type::Boolean.new.cast("") }
case_run("type_bool_nil")           { ActiveModel::Type::Boolean.new.cast(nil) }
case_run("type_bool_false")         { ActiveModel::Type::Boolean.new.cast(false) }
case_run("type_int_str")            { ActiveModel::Type::Integer.new.cast("42") }
case_run("type_int_bad")            { ActiveModel::Type::Integer.new.cast("abc") }
case_run("type_int_float")          { ActiveModel::Type::Integer.new.cast(4.5) }
case_run("type_int_nil")            { ActiveModel::Type::Integer.new.cast(nil) }
case_run("type_string_nil")         { ActiveModel::Type::String.new.cast(nil) }
case_run("type_string_int")         { ActiveModel::Type::String.new.cast(7) }
case_run("type_float_str")          { ActiveModel::Type::Float.new.cast("4.25") }
case_run("type_lookup_int")         { ActiveModel::Type.lookup(:integer).class }
case_run("type_lookup_string")      { ActiveModel::Type.lookup(:string).class }
case_run("type_lookup_bool")        { ActiveModel::Type.lookup(:boolean).class }

# --- SecurePassword --------------------------------------------------------

case_run("sp_blank_invalid")        { u = UserP.new; u.valid?; u.errors.details }
case_run("sp_authenticate_ok")      { u = UserP.new; u.password = "secret"; u.authenticate("secret") ? true : false }
case_run("sp_authenticate_bad")     { u = UserP.new; u.password = "secret"; u.authenticate("nope") ? true : false }
case_run("sp_too_long_invalid")     { u = UserP.new; u.password = "x" * 73; u.valid?; u.errors.details.keys }
case_run("sp_too_long_auth_ok")     { u = UserP.new; u.password = "x" * 73; u.authenticate("x" * 73) ? true : false }
case_run("sp_too_long_alias")       { u = UserP.new; u.password = "x" * 72 + "abc"; u.authenticate("x" * 72 + "zzz") ? true : false }
case_run("sp_digest_present_valid") { u = UserP.new; u.password = "secret"; u.valid? }
case_run("sp_confirmation_mism")    { u = UserP.new; u.password = "secret"; u.password_confirmation = "other"; u.valid?; u.errors.details.keys }
case_run("sp_digest_kind")          { u = UserP.new; u.password = "secret"; u.password_digest.start_with?("$2a$") }

# --- ForbiddenAttributesProtection / Access --------------------------------

case_run("forbidden_hash")          { p = Prot.new; p.send(:sanitize_for_mass_assignment, {name: "x"}) }
case_run("forbidden_raise")         { p = Prot.new; bad = Object.new; def bad.permitted? = false; def bad.to_h = {name: "y"}; p.send(:sanitize_for_mass_assignment, bad); "no-raise" }
case_run("forbidden_assign_ok")     { p = Prot.new; p.assign_attributes(name: "N"); p.name }
case_run("access_slice")            { Acc.new("q").slice(:name) }
case_run("access_values_at")        { Acc.new("q").values_at(:name) }
case_run("access_attributes")       { Acc.new("q").attributes }
