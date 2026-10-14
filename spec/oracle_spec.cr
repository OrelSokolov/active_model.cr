# Oracle spec: 1:1 mirror of oracle/cases.rb. Expected values live in
# oracle/expected.yml — captured from the ORIGINAL activemodel 8.1.4.
# The port must reproduce them exactly; tests are never edited on either
# side (see AGENTS.md / oracle/rails-tests for the original minitest
# suites).
#
# Documented call-form deviations (asserted OUTPUTS are identical):
# - `if:`/`unless:` → `condition:`/`unless_condition:` (Ruby keywords)
# - custom validator registry: `register_validator("upcase", ...)` up front
#   (Ruby resolves `UpcaseValidator` via runtime const-get)
# - callback terminator: method-name Symbol instead of a lambda
# - errors.add takes (attr, type)/(attr, message) overloads; the Ruby
#   `message:`/`value:` kwargs don't affect any asserted value (details
#   keep only :error — oracle err_details); the attribute argument is a
#   Symbol literal (the port needs it for the Symbol-keyed
#   details/attribute_names views — Ruby accepts both forms).

require "spec"
require "../src/active_model_cr"

EXPECTED = Hash(String, String).new
File.read_lines("#{__DIR__}/../oracle/expected.yml").each do |line|
  next if line.empty?
  id, value = line.split('\t', 2)
  EXPECTED[id] = value
end

def r(v : Bool | Int32 | Int64 | Float64 | String) : String
  v.inspect
end

def r(v : Nil) : String
  "nil"
end

def r(v : Symbol) : String
  ":#{v}"
end

def r(v : Array) : String
  "A[#{v.map { |e| r(e) }.join(",")}]"
end

def r(v : Hash) : String
  pairs = [] of String
  v.keys.sort_by(&.to_s).each do |k|
    pairs << "#{r(k)}=>#{r(v[k])}"
  end
  "H{#{pairs.join(",")}}"
end

def r(v : NamedTuple) : String
  pairs = [] of String
  v.each { |k, val| pairs << "#{r(k)}=>#{r(val)}" }
  "H{#{pairs.sort.join(",")}}"
end

def r(v : Class) : String
  v.name
end

# Cases are evaluated eagerly at load time (like the Ruby oracle's
# case_run) and the rendered result is captured — Crystal 1.21 captured
# blocks (`&block` + `block.call`) always return Nil, so the value must
# come from `yield`.
def c(id : String, &)
  expected = EXPECTED[id]? || raise "missing expected.yml entry: #{id}"
  actual = begin
    r(yield)
  rescue e : Exception
    "raise:#{e.class.name}"
  end
  it(id) { actual.should eq(expected), "expected #{expected.inspect}, got #{actual.inspect}" }
end

# --- test models (mirror of oracle/cases.rb) -------------------------

class Person
  include ActiveModel::Model
  attribute :name
  attribute :age
  validates :name, presence: true
end

class ApiModel
  include ActiveModel::API
  attribute :email
  validates :email, presence: true
end

class Rec
  include ActiveModel::Conversion

  def initialize(@id : ActiveModel::Value)
  end

  def id : ActiveModel::Value
    @id
  end

  def persisted? : Bool
    !@id.nil?
  end
end

class Series
  include ActiveModel::Model
end

class StrictP
  include ActiveModel::Model
  attribute :name
  validates! :name, presence: true
end

class VModel
  include ActiveModel::Model
  attribute :a
  attribute :b
  attribute :c
  attribute :d
  attribute :terms
  attribute :state
  validates :a, presence: true
  validates :b, absence: true
  validates :c, length: {minimum: 2, maximum: 5}
  validates :d, format: {with: /\A\d+\z/}
  validates :a, confirmation: true
  validates :terms, acceptance: true
  validates :state, inclusion: {in: %w[open closed]}
end

class NModel
  include ActiveModel::Model
  attribute :n
  attribute :m
  validates :n, numericality: true
  validates :m, numericality: {only_integer: true, greater_than: 5, less_than_or_equal_to: 10}
end

class CtxModel
  include ActiveModel::Model
  attribute :x
  attribute :y
  validates :x, presence: true, on: :create
  validates :y, presence: true, on: :update
end

class CondModel
  include ActiveModel::Model
  attribute :a
  attribute :b
  validates :a, presence: true, condition: :b
end

class UpcaseValidator < ActiveModel::EachValidator
  def validate_each(record : ActiveModel::Validations, attribute : String, value : ActiveModel::Value) : Nil
    unless value.is_a?(String) && value == value.upcase
      record.errors.add(attribute, "not upcase", :invalid)
    end
  end
end

ActiveModel::Validations.register_validator("upcase", UpcaseValidator)

class CustModel
  include ActiveModel::Model
  attribute :code
  validates :code, upcase: true
  validate :must_start_with_z

  def must_start_with_z
    errors.add("code", "must start with Z") unless code.as?(String).try(&.starts_with?("Z"))
  end
end

class DirtyModel
  include ActiveModel::Attributes
  include ActiveModel::Dirty
  attribute :name, :string
end

class UserP
  include ActiveModel::SecurePassword
  attribute :password_digest, :string
  has_secure_password
end

class BadParams
  include ActiveModel::MassAssignmentParameters

  def permitted? : Bool
    false
  end

  def to_h
    {:name => "y"}
  end
end

class Prot
  # Port note: ForbiddenAttributesProtection must be included AFTER
  # AttributeAssignment — its __sanitize overloads replace the generic
  # pass-through (last include wins in Crystal; Ruby needs no order
  # because AA doesn't define sanitize there).
  include ActiveModel::AttributeAssignment
  include ActiveModel::Attributes
  include ActiveModel::ForbiddenAttributesProtection
  attribute :name
end

class Acc
  include ActiveModel::Access

  def initialize(@n : String)
  end

  def name : String
    @n
  end

  def attributes : Hash(String, ActiveModel::Value)
    {"name" => @n} of String => ActiveModel::Value
  end
end

class Ser
  include ActiveModel::Model
  include ActiveModel::Serializers::JSON
  attribute :name
  attribute :age
  serialize_method :shout

  def shout : String
    "#{name}!"
  end
end

class TypedSer
  include ActiveModel::AttributeAssignment
  include ActiveModel::Attributes
  include ActiveModel::Serializers::JSON
  attribute :age, :integer
end

class Attrs
  include ActiveModel::Attributes
  attribute :age, :integer, default: 7
  attribute :note
end

class Cb
  include ActiveModel::Callbacks
  define_callbacks :save
  set_callback :save, :before, :mark_before
  set_callback :save, :after, :mark_after
  set_callback :save, :around do
    log << :around_in
    yield
    log << :around_out
  end

  @log = [] of Symbol

  def log : Array(Symbol)
    @log
  end

  def mark_before
    @log << :before
  end

  def mark_after
    @log << :after
  end

  def run
    run_callbacks(:save) { @log << :yield }
    @log
  end
end

class CbAbort
  include ActiveModel::Callbacks
  define_callbacks :save, terminator: :never_halt
  set_callback :save, :before do
    log << :stopped
    throw :abort
  end

  @log = [] of Symbol

  def log : Array(Symbol)
    @log
  end

  # Gem quirk (oracle cb_abort): a terminator that compares the result
  # proc without calling it never invokes the callback and never halts.
  def never_halt(rl : Proc(Nil)) : Bool
    false
  end

  def run
    run_callbacks(:save) { @log << :yield }
    @log
  end
end

class BogusKlass
  include ActiveModel::Model
  attribute :name
  validates :name, bogus: true
end

# --- cases -------------------------------------------------------------

describe "active_model oracle" do
  # Naming / Translation
  c("naming_param_key")        { Person.model_name.param_key }
  c("naming_route_key")        { Person.model_name.route_key }
  c("naming_singular_route")   { Person.model_name.singular_route_key }
  c("naming_i18n_key")         { Person.model_name.i18n_key.to_s }
  c("naming_human")            { Person.model_name.human }
  c("naming_name")             { Person.model_name.name }
  c("naming_uncount_route")    { Series.model_name.route_key }
  c("naming_uncount_sroute")   { Series.model_name.singular_route_key }
  c("translation_human_attr")  { Person.human_attribute_name(:first_name) }

  # Conversion
  c("conv_to_key_new")         { Rec.new(nil).to_key }
  c("conv_to_param_new")       { Rec.new(nil).to_param }
  c("conv_to_key_persisted")   { Rec.new(42).to_key }
  c("conv_to_param_persisted") { Rec.new(42).to_param }
  c("conv_to_model")           { rm = Rec.new(1); rm.to_model.same?(rm) }
  c("api_persisted")           { ApiModel.new(email: "e").persisted? }
  c("api_to_param")            { ApiModel.new(email: "e").to_param }
  c("api_model_name")          { ApiModel.new(email: "e").model_name.name }
  c("api_to_partial_path")     { ApiModel.new(email: "e").to_partial_path }

  # Model / API / AttributeAssignment
  c("model_assign")            { p = Person.new(name: "Ann", age: 3); "#{p.name}/#{p.age}" }
  c("model_valid")             { Person.new(name: "Ann").valid? }
  c("model_invalid")           { Person.new(age: 1).valid? }
  c("model_invalid_msgs")      { m = Person.new(age: 1); m.valid?; m.errors.full_messages }
  c("model_unknown_kwarg")     { Person.new(bogus: 1); "no-raise" }
  c("model_unknown_assign")    { p = Person.new; p.assign_attributes({bogus: 1}); "no-raise" }
  c("assign_string_keys")      { p = Person.new; p.assign_attributes({"name" => "Bo"}); p.name }
  c("model_name_on_instance")  { Person.new(name: "x").model_name.param_key }

  # Validations
  c("val_presence_blank")      { v = VModel.new(a: nil); v.valid?; v.errors["a"] }
  c("val_presence_ok")         { VModel.new(a: "x").valid? }
  c("val_absence")             { v = VModel.new(a: "x", b: "set"); v.valid?; v.errors["b"] }
  c("val_length_short")        { v = VModel.new(a: "x", c: "a"); v.valid?; v.errors["c"] }
  c("val_length_long")         { v = VModel.new(a: "x", c: "abcdef"); v.valid?; v.errors["c"] }
  c("val_length_boundary_min") { VModel.new(a: "x", c: "ab", d: "1", terms: "1", state: "open", b: nil, a_confirmation: "x").valid? }
  c("val_format_bad")          { v = VModel.new(a: "x", d: "12x"); v.valid?; v.errors["d"] }
  c("val_confirmation_mism")   { v = VModel.new(a: "x", a_confirmation: "y"); v.valid?; v.errors["a"] }
  c("val_acceptance_unset")    { v = VModel.new(a: "x", a_confirmation: "x"); v.valid?; v.errors["terms"] }
  c("val_inclusion_out")       { v = VModel.new(a: "x", state: "gone"); v.valid?; v.errors["state"] }
  c("val_numericality_str")    { v = NModel.new(n: "4.5", m: 7); v.valid?; v.errors["n"] }
  c("val_numericality_bool")   { v = NModel.new(n: true); v.valid?; v.errors["n"] }
  c("val_num_int_gt")          { v = NModel.new(n: 1, m: 5); v.valid?; v.errors["m"] }
  c("val_num_int_lte")         { NModel.new(n: 1, m: 10).valid? }
  c("val_num_int_gt_ok")       { NModel.new(n: 1, m: 6).valid? }
  c("val_num_float_not_int")   { v = NModel.new(n: 1, m: 6.5); v.valid?; v.errors["m"] }
  c("val_context_create_x")    { m = CtxModel.new(y: 1); m.valid?(:create); m.errors["x"] }
  c("val_context_create_y_ok") { m = CtxModel.new(x: 1); m.valid?(:create) }
  c("val_context_update_y")    { m = CtxModel.new(x: 1); m.valid?(:update); m.errors["y"] }
  c("val_context_default")     { m = CtxModel.new; m.valid?; m.errors.attribute_names }
  c("val_if_b_true")           { m = CondModel.new(b: true); m.valid?; m.errors["a"] }
  c("val_if_b_false")          { CondModel.new(b: false).valid? }
  c("val_custom_each")         { m = CustModel.new(code: "abc"); m.valid?; m.errors["code"] }
  c("val_custom_method")       { m = CustModel.new(code: "QAB"); m.valid?; m.errors["code"] }
  c("val_custom_ok")           { CustModel.new(code: "ZAB").valid? }
  c("val_strict_raise")        { StrictP.new.valid?; "no-raise" }
  c("val_unknown_validator")   { BogusKlass.new(name: "x").valid?; "no-raise" }

  # Errors
  c("err_add_msgs")            { m = Person.new; m.errors.add(:name,:blank); m.errors[:name] }
  c("err_add_custom")          { m = Person.new; m.errors.add(:name,"custom text"); m.errors[:name] }
  c("err_details")             { m = Person.new; m.errors.add(:name,:invalid); m.errors.details[:name] }
  c("err_full_messages")       { m = Person.new; m.errors.add(:name,:blank); m.errors.full_messages }
  c("err_full_messages_for")   { m = Person.new; m.errors.add(:age,:not_a_number); m.errors.full_messages_for(:age) }
  c("err_where")               { m = Person.new; m.errors.add(:name,:blank); m.errors.add(:name,:invalid); m.errors.where(:name, :blank).size }
  c("err_added")               { m = Person.new; m.errors.add(:name,:blank); m.errors.added?(:name, :blank) }
  c("err_added_false")         { m = Person.new; m.errors.added?(:name, :blank) }
  c("err_include")             { m = Person.new; m.errors.add(:name,:blank); m.errors.include?(:name) }
  c("err_count")               { m = Person.new; m.errors.add(:name,:blank); m.errors.add(:age,:blank); m.errors.count }
  c("err_empty")               { Person.new.errors.empty? }
  c("err_delete")              { m = Person.new; m.errors.add(:name,:blank); m.errors.delete(:name); m.errors.count }
  c("err_attribute_names")     { m = Person.new; m.errors.add(:name,:blank); m.errors.add(:age,:blank); m.errors.attribute_names }
  c("err_as_json")             { m = Person.new; m.errors.add(:name,:blank); m.errors.as_json }
  c("err_invalid_interactive") { m = NModel.new(n: 1, m: 5); m.valid?; m.errors.full_messages_for(:m) }

  # Dirty
  c("dirty_initial")           { d = DirtyModel.new; [d.changed?, d.changed, d.changes] }
  c("dirty_changed")           { d = DirtyModel.new; d.name = "bob"; d.changed? }
  c("dirty_changed_list")      { d = DirtyModel.new; d.name = "bob"; d.changed }
  c("dirty_changes")           { d = DirtyModel.new; d.name = "bob"; d.changes }
  c("dirty_was")               { d = DirtyModel.new; d.name = "bob"; d.name_was }
  c("dirty_attr_changed_q")    { d = DirtyModel.new; d.name = "bob"; d.name_changed? }
  c("dirty_attr_change")       { d = DirtyModel.new; d.name = "bob"; d.name_change }
  c("dirty_applied")           { d = DirtyModel.new; d.name = "bob"; d.changes_applied; d.changed? }
  c("dirty_prev_changed")      { d = DirtyModel.new; d.name = "bob"; d.changes_applied; d.name = "rob"; [d.name_previously_changed?, d.name_previous_change] }
  c("dirty_prev_change_same")  { d = DirtyModel.new; d.name = "bob"; d.changes_applied; d.name = "bob"; d.name_previously_changed? }
  c("dirty_restore")           { d = DirtyModel.new; d.name = "bob"; d.changes_applied; d.name = "rob"; d.restore_attributes; [d.name, d.changed?] }
  c("dirty_same_value")        { d = DirtyModel.new; d.name = nil; d.changed? }
  c("dirty_changed_attrs")     { d = DirtyModel.new; d.name = "bob"; d.changed_attributes.keys }

  # Callbacks
  c("cb_order")                { Cb.new.run }
  c("cb_abort")                { CbAbort.new.run }

  # Serialization
  c("ser_as_json")             { Ser.new(name: "a", age: 1).as_json }
  c("ser_as_json_methods")     { Ser.new(name: "a").as_json(methods: [:shout]) }
  c("ser_serializable_only")   { Ser.new(name: "a", age: 2).serializable_hash(only: [:name]) }
  c("ser_serializable_except") { Ser.new(name: "a", age: 2).serializable_hash(except: [:name]) }
  c("ser_to_json")             { Ser.new(name: "a").to_json }
  c("ser_from_json")           { s = Ser.new; s.from_json(%({"name":"z","age":"5"})); [s.name, s.age] }
  c("ser_from_json_types")     { s = Ser.new; s.from_json(%({"name":"z","age":"5"})); s.age.class }
  c("ser_from_json_typed")     { t = TypedSer.new; t.from_json(%({"age":"5"})); t.age }
  c("ser_typed_writer")        { t = TypedSer.new; t.age = "7"; t.age }
  c("ser_typed_assign")        { t = TypedSer.new; t.assign_attributes({age: "9"}); t.age }

  # Attributes / Type
  c("attrs_default")           { Attrs.new.age }
  c("attrs_hash")              { Attrs.new.attributes }
  c("attrs_cast_write")        { a = Attrs.new; a.age = "9"; a.age }
  c("attrs_string_nil")        { Attrs.new.note }
  c("type_bool_zero")          { ActiveModel::Type::Boolean.new.cast("0") }
  c("type_bool_one")           { ActiveModel::Type::Boolean.new.cast("1") }
  c("type_bool_empty")         { ActiveModel::Type::Boolean.new.cast("") }
  c("type_bool_nil")           { ActiveModel::Type::Boolean.new.cast(nil) }
  c("type_bool_false")         { ActiveModel::Type::Boolean.new.cast(false) }
  c("type_int_str")            { ActiveModel::Type::Integer.new.cast("42") }
  c("type_int_bad")            { ActiveModel::Type::Integer.new.cast("abc") }
  c("type_int_float")          { ActiveModel::Type::Integer.new.cast(4.5) }
  c("type_int_nil")            { ActiveModel::Type::Integer.new.cast(nil) }
  c("type_string_nil")         { ActiveModel::Type::String.new.cast(nil) }
  c("type_string_int")         { ActiveModel::Type::String.new.cast(7) }
  c("type_float_str")          { ActiveModel::Type::Float.new.cast("4.25") }
  c("type_lookup_int")         { ActiveModel::Type.lookup(:integer) }
  c("type_lookup_string")      { ActiveModel::Type.lookup(:string) }
  c("type_lookup_bool")        { ActiveModel::Type.lookup(:boolean) }

  # SecurePassword
  c("sp_blank_invalid")        { u = UserP.new; u.valid?; u.errors.details }
  c("sp_authenticate_ok")      { u = UserP.new; u.password = "secret"; u.authenticate("secret") }
  c("sp_authenticate_bad")     { u = UserP.new; u.password = "secret"; u.authenticate("nope") }
  c("sp_too_long_invalid")     { u = UserP.new; u.password = "x" * 73; u.valid?; u.errors.details.keys }
  c("sp_too_long_auth_ok")     { u = UserP.new; u.password = "x" * 73; u.authenticate("x" * 73) }
  c("sp_too_long_alias")       { u = UserP.new; u.password = "x" * 72 + "abc"; u.authenticate("x" * 72 + "zzz") }
  c("sp_digest_present_valid") { u = UserP.new; u.password = "secret"; u.valid? }
  c("sp_confirmation_mism")    { u = UserP.new; u.password = "secret"; u.password_confirmation = "other"; u.valid?; u.errors.details.keys }
  c("sp_digest_kind")          { u = UserP.new; u.password = "secret"; u.password_digest.as(String).starts_with?("$2a$") }

  # ForbiddenAttributesProtection / Access
  c("forbidden_hash")          { p = Prot.new; p.__sanitize({name: "x"}) }
  c("forbidden_raise")         { p = Prot.new; p.__sanitize(BadParams.new); "no-raise" }
  c("forbidden_assign_ok")     { p = Prot.new; p.assign_attributes({name: "N"}); p.name }
  c("access_slice")            { Acc.new("q").slice(:name) }
  c("access_values_at")        { Acc.new("q").values_at(:name) }
  c("access_attributes")       { Acc.new("q").attributes }
end
