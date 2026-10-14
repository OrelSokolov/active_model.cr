# active_model_cr — port of Rails ActiveModel 8.1.4 (namespace `ActiveModel`,
# 1:1 to the gem; see PLAN.md for the module map and deviations).
require "json"
require "crypto/bcrypt"
require "active_support_cr"

module ActiveModel
  VERSION = "8.1.4-cr.0"

  # Runtime attribute value: what AM stores in attribute sets and what the
  # JSON layer passes around (JSON::Any is converted into this).
  alias Value = Nil | Bool | Int32 | Int64 | Float64 | String | Array(Value) | Hash(String, Value)
end

require "./exceptions"
require "./type"
require "./naming"
require "./translation"
require "./conversion"
require "./access"
require "./attributes"
require "./attribute_assignment"
require "./forbidden_attributes_protection"
require "./errors"
require "./validations"
require "./secure_password"
require "./model"
require "./dirty"
require "./callbacks"
require "./serialization"
