# Paypal Express does not give us separate first/last name fields.
# We'll try to separate the given name to first/last name parts, but
# in the case where they can't be separated we remove the validation
# for the last name.
Spree::Address._validators.reject! do |key, validators|
  if key == :lastname
    validators.first.attributes.delete(:lastname)
    true
  else
    false
  end
end
