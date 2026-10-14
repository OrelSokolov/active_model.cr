# Probe activemodel 8.1.4 API surface before writing oracle cases.
require "active_model"
require "active_model/serializers/json"

puts "== Name class:"
class Person
  include ActiveModel::Model
  attr_accessor :name, :age
  validates :name, presence: true
end
p Person.model_name.respond_to?(:param_key)
p Person.model_name.param_key
p Person.model_name.route_key
p Person.model_name.singular_route_key
p Person.model_name.i18n_key
p Person.model_name.human
p Person.human_attribute_name(:first_name)

puts "== Model basics:"
m = Person.new(name: "A", age: 3)
p m.valid?
p Person.new(age: 1).valid?
p Person.new(age: 1).errors.full_messages

puts "== API:"
class ApiModel
  include ActiveModel::API
  attr_accessor :email
  validates :email, presence: true
end
a = ApiModel.new(email: "x@y.z")
p a.valid?, a.persisted?, a.to_param, a.model_name.name
p ApiModel.ancestors.grep(Class).first(4)

puts "== Dirty:"
class DirtyModel
  include ActiveModel::Attributes
  include ActiveModel::Dirty
  attribute :name, :string
end
d = DirtyModel.new
d.name = "bob"
p d.changed?, d.changed, d.changes.keys, d.name_was
d.changes_applied
p d.changed?
d.name = "rob"
p d.name_previously_changed?, d.name_previous_change
d.restore_attributes
p d.name, d.changed?

puts "== SecurePassword:"
class UserP
  include ActiveModel::SecurePassword
  attr_accessor :password_digest
  has_secure_password
end
u = UserP.new
p u.valid?, u.errors.details
u.password = "secret"
p u.authenticate("secret") ? true : false
p u.authenticate("nope") ? true : false
u2 = UserP.new
u2.password = "x" * 73
p u2.valid?, u2.errors.details.keys
p u2.authenticate("x" * 73) ? true : false

puts "== Type:"
p ActiveModel::Type::Boolean.new.cast("0")
p ActiveModel::Type::Boolean.new.cast("")
p ActiveModel::Type::Integer.new.cast("42")
p ActiveModel::Type.lookup(:integer).class
p ActiveModel::Type.lookup(:string).class

puts "== Forbidden:"
class Prot
  include ActiveModel::ForbiddenAttributesProtection
  attr_accessor :name
end
pr = Prot.new
p pr.send(:sanitize_for_mass_assignment, {name: "x"})
bad = Object.new
def bad.permitted? = false
def bad.to_h = {name: "y"}
begin
  pr.send(:sanitize_for_mass_assignment, bad)
rescue => e
  p e.class.name
end

puts "== Access:"
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
ac = Acc.new("q")
p ac.slice(:name)
p ac.values_at(:name)

puts "== Serialization:"
class Ser
  include ActiveModel::Model
  include ActiveModel::Serializers::JSON
  attr_accessor :name, :age
  def initialize(name: "a", age: 1)
    @name = name
    @age = age
  end
  def attributes
    {"name" => nil, "age" => nil}
  end
  def shout
    "#{name}!"
  end
end
s = Ser.new
p s.as_json(methods: [:shout])
s.from_json(%({"name":"z","age":"5"}))
p [s.name, s.age]

puts "== Attributes:"
class Attrs
  include ActiveModel::Attributes
  attribute :age, :integer, default: 7
end
at = Attrs.new
p at.age, at.attributes
at.age = "9"
p at.age

puts "== Callbacks:"
class Cb
  extend ActiveModel::Callbacks
  define_callbacks :save
  set_callback :save, :before do |o| o.log << :before end
  set_callback :save, :after do |o| o.log << :after end
  attr_accessor :log
  def initialize = @log = []
  def run = run_callbacks(:save) { @log << :yield }
end
p Cb.new.run

puts "== Naming uncountable:"
class Series
  include ActiveModel::Model
end
p Series.model_name.route_key
p Series.model_name.singular_route_key

puts "== Strict:"
begin
  Person.validates! :age, presence: true
rescue => e
  p e.class.name
end

puts "== Errors:"
m2 = Person.new
m2.errors.add(:name, :blank)
m2.errors.add(:name, :invalid, message: "custom")
p m2.errors[:name]
p m2.errors.details
p m2.errors.where(:name, :blank).size
p m2.errors.full_messages_for(:name)
p m2.errors.added?(:name, :blank)
p m2.errors.count
