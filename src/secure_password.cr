# ActiveModel::SecurePassword — has_secure_password 1:1 with the gem's
# observable behavior (oracle cases sp_*), including the documented
# bcrypt quirks:
# - validation is advisory: `valid?` rejects > 72 bytes, but `authenticate`
#   succeeds anyway (bcrypt silently truncates — sp_too_long_auth_ok,
#   sp_too_long_alias).
# - the host MUST declare the digest attribute itself (gem quirk, kept).
# - Crystal's crypto/bcrypt raises past 71 bytes (it appends a NUL), so the
#   practical cap is 71 — same deviation as devise.cr/src/encryptor.cr.
require "crypto/bcrypt"

module ActiveModel
  module SecurePassword
    include ActiveModel::Attributes
    include ActiveModel::Validations

    MAX_PASSWORD_LENGTH_ALLOWED = 72

    # The validations ride the normal validation chain: the generated
    # method is appended to __run_validations via previous_def (the gem
    # includes ActiveModel::Validations for the same effect).
    macro has_secure_password(attribute = :password)
      {% unless @type.methods.any? { |m| m.name.stringify == "__run_validations" } %}
        __plant_validation_base
      {% end %}
      @__sp_{{attribute.id}} : String? = nil
      @__sp_{{attribute.id}}_confirmation : String? = nil

      def {{attribute.id}} : String?
        @__sp_{{attribute.id}}
      end

      def {{attribute.id}}=(value : String?)
        @__sp_{{attribute.id}} = value
        return if value.nil?
        __write_attribute({{attribute.id.stringify}} + "_digest",
          Crypto::Bcrypt::Password.create(value.byte_slice(0, 71), cost: 12).to_s)
      end

      def {{attribute.id}}_confirmation : String?
        @__sp_{{attribute.id}}_confirmation
      end

      def {{attribute.id}}_confirmation=(value : String?)
        @__sp_{{attribute.id}}_confirmation = value
      end

      def authenticate(password : String?) : Bool
        digest = __read_attribute({{attribute.id.stringify}} + "_digest").as?(String)
        return false if digest.nil? || digest.empty?
        begin
          bcrypt = Crypto::Bcrypt::Password.new(digest)
          rehashed = Crypto::Bcrypt.new(password.to_s.byte_slice(0, 71), bcrypt.salt, bcrypt.cost).to_s
          rehashed == digest
        rescue Crypto::Bcrypt::Error
          false
        end
      end

      def validation__secure_password_{{attribute.id}}(context : Symbol?) : Nil
        digest = __read_attribute({{attribute.id.stringify}} + "_digest")
        pw = @__sp_{{attribute.id}}
        if digest.nil? || (digest.as?(String).try(&.empty?) == true)
          errors.add({{attribute}}, "can't be blank", :blank)
        end
        if pw && pw.bytesize > MAX_PASSWORD_LENGTH_ALLOWED
          errors.add({{attribute}}, "is too long", :password_too_long)
        end
        conf = @__sp_{{attribute.id}}_confirmation
        if !conf.nil? && conf != pw
          errors.add(:"{{attribute.id}}_confirmation",
            "doesn't match {{attribute.id.stringify.capitalize.id}}", :confirmation)
        end
      end

      def __run_validations(context : Symbol?) : Nil
        previous_def
        validation__secure_password_{{attribute.id}}(context)
      end
    end
  end
end
