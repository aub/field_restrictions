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
    
    validate :ensure_no_restricted_attribute_changes
  end

  def as(user)
    if Restrictor.restrictions_for(self)
      AsWrappers::ActiveRecordClassAsWrapper.new(self, user)
    else
      self
    end
  end
    
  module InstanceMethods
    def permitted?(user, attributes, operator=:or)
      FieldRestrictions::Restrictor.permitted?(user, self, attributes, operator)
    end
    
    def add_restricted_attribute_change(attribute)
      @restricted_attribute_changes ||= []
      @restricted_attribute_changes << attribute unless @restricted_attribute_changes.include?(attribute)
    end
    
    def ensure_no_restricted_attribute_changes
      message = 'is restricted from the current user'
      (@restricted_attribute_changes || []).each do |attribute|
        errors.add(attribute, message) unless Array(errors.on(attribute)).include?(message)
      end
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
      
      def method_missing(method, *args, &block)
        if method.to_s.match('^find.*')
          result = @clazz.send(method, *args, &block)
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

    [:first, :last, :all].each do |method|
      define_method "#{method}" do |*args|
        result = @proxy.send(method, *args)
        Array(result).each do |model|
          FieldRestrictions::Restrictor.restrict_model model, @user
        end
        result
      end
    end
    
    def method_missing(method, *args, &block)
      if method.to_s.match('^find.*')
        result = @proxy.send(method, *args, &block)
        return result if result.nil?
        
        if result.kind_of?(Enumerable)
          result.each do |model|
            Restrictor::restrict_model model, @user
          end
        elsif result.kind_of?(ActiveRecord::Base)
          Restrictor::restrict_model result, @user
        end
        result
      elsif Restrictor::permitted!(@user, @model, @attribute_name)
        @proxy.send(method, *args, &block)
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
        end
      end
    end
    
    def self.permitted?(user, model, attribute_names, operator=:or)
      results = Array(attribute_names).collect { |a| permitted_for_attribute?(user, model, a) }
      (operator == :and) ? results.all? : results.any?
    end

    def self.permitted!(user, model, attribute_names, operator=:or)
      unless permitted?(user, model, attribute_names, operator)
        if attribute_names.kind_of?(Array)
          attribute_names.each do |attribute|
            model.add_restricted_attribute_change(attribute)
          end
        else
          model.add_restricted_attribute_change(attribute_names)
        end
        false
      else
        true
      end
    end

    def self.permitted_for_attribute?(user, model, attribute)
      rules = restrictions_for(model.class)
      return true if rules.empty?
      
      rule = rules[attribute]
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
    
    private
    
    RESTRICTIONS = {}    
  end
end

