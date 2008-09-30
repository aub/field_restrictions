#Publication.as(user).[find, create, new]

class RestrictedAttributeError < StandardError; end

module FieldRestrictions
  
  def restrict(fields, args={})
    raise ArgumentError, 'Either a :to or :from field is required.' unless args[:to] || args[:from]
    raise ArgumentError, 'Provide either a :to or :from field, but not both.' if args[:to] && args[:from]
  
    include InstanceMethods unless included_modules.include?(InstanceMethods)
  
    Array(fields).each do |field|
      Restrictor.add_restrictions_for(self, field, args)
    end
  end

  def as(user)
    if Restrictor.restrictions_for(self)
      AsWrappers::ActiveRecordClassAsWrapper.new(self, user)
    else
      self
    end
  end
    
  module InstanceMethods
    def if_permitted(user, attribute, &block)
      yield if FieldRestrictions::Restrictor.permitted?(user, self, attribute)
    end
  end
    
  module AsWrappers
    
    class ActiveRecordClassAsWrapper
      
      def initialize(clazz, user)
        @clazz, @user = clazz, user
      end
      
      def create(attrs)
        result = @clazz.new
        Restrictor.restrict_model(result, @user)
        result.attributes = attrs
        result.save
        result
      end
      
      def new(attrs)
        result = @clazz.new
        Restrictor.restrict_model(result, @user)
        result.attributes = attrs
        result
      end
      
      def method_missing(method, *args)
        if method.to_s.match('^find.*')
          result = @clazz.send(method, *args)
          return result if result.nil?
          
          if result.kind_of?(Enumerable)
            result.each do |model|
              Restrictor::restrict_model model, @user
            end
          elsif result.kind_of?(ActiveRecord::Base)
            Restrictor::restrict_model result, @user
          end
          result
        end
      end      
    end
  end
  
  class AssociationProxyWrapper
    
    def initialize(proxy, user, model, attribute_name)
      @proxy, @user, @model, @attribute_name = proxy, user, model, attribute_name
    end
    
    def create(attrs={})
      Restrictor::permitted!(@user, @model, @attribute_name)
      result = @proxy.build
      Restrictor.restrict_model(result, @user)
      result.attributes = attrs
      result.save
      result
    end

    def build(attrs={})
      Restrictor::permitted!(@user, @model, @attribute_name)
      result = @proxy.build
      Restrictor.restrict_model(result, @user)
      result.attributes = attrs
      result
    end

    alias_method :new, :build
    
    def method_missing(method, *args)
      if Restrictor::permitted!(@user, @model, @attribute_name)
        @proxy.send(method, *args)
      end
    end
  end
  
  module Restrictor
        
    def self.restrictions_for(clazz)
      result = {}
      while clazz
        result.reverse_merge!(RESTRICTIONS[clazz]) if RESTRICTIONS[clazz]
        clazz = clazz.superclass
      end
      result
    end
    
    def self.add_restrictions_for(clazz, field, rules)
      RESTRICTIONS[clazz] ||= {}
      RESTRICTIONS[clazz][field] = rules
    end
        
    def self.restrict_model(model_arg, user_arg)
      model, user = model_arg, user_arg
      restrictions = restrictions_for(model.class)
      model_class = model.class
      model.instance_eval do
        (class << self; self; end).class_eval do
          include(Module.new do
            restrictions.each do |attribute, rule|
              define_method "#{attribute}=" do |value|
                roles = user.roles_for(self)                
                if FieldRestrictions::Restrictor.permitted!(user, self, attribute)
                  super
                end
              end
            end
            
            model_class.reflections.each do |key, reflection|
              define_method "#{key}" do
                result = super
                if result.kind_of?(Enumerable)
                  result.each do |item|
                    FieldRestrictions::Restrictor.restrict_model item, user
                  end
                elsif result.kind_of?(ActiveRecord::Base)
                  FieldRestrictions::Restrictor.restrict_model result, user
                end
                
                if FieldRestrictions::Restrictor.restrictions_for(self.class)[key]
                  FieldRestrictions::AssociationProxyWrapper.new(result, user, self, key)
                else
                  result
                end
              end
            end
          end)
        end
      end
    end
    
    def self.permitted?(user, model, attribute_name)
      rules = restrictions_for(model.class)
      return true if rules.empty?
      
      rule = rules[attribute_name]
      return true if rule.blank?
      
      roles = user.roles_for(model)
      if roles.empty?
        result = false
      elsif rule[:to]
        result = Array(rule[:to]).any? { |r| roles.include?(r) }
      elsif rule[:from]
        result = !Array(rule[:from]).any? { |r| roles.include?(r) }
      end
    end

    def self.permitted!(user, model, attribute_name)
      if permitted?(user, model, attribute_name)
        true
      else
        raise RestrictedAttributeError, "You do not have permission to edit the attribute #{attribute_name}"
      end
    end
    
    private
    
    RESTRICTIONS = {}    
  end
end

