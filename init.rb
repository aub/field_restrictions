require 'field_restrictions'

ActiveRecord::Base.send(:extend, FieldRestrictions)