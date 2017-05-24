module OmniDataObjects
  # TODO: Validate :to => :one or :many
  # TODO: Require & validate delete rule name
  class Relationship < Property
    attr_reader :target, :inverse, :many, :delete

    def initialize(entity, name, target, inverse, options = {})
      super(entity, name, options)
      @target = target
      @inverse = inverse
      @many = options[:many]
      @delete = options[:delete].to_s
    end

    def process
      super
      
      t = entity.model.entity_named(target)
      fail "Relationship #{entity.name}.#{name} specifies a target entity #{target} that cannot be found" unless t
      @target = t
      
      inv = target.property_named(inverse)
      fail "Relationship #{entity.name}.#{name} specifies an inverse relationship of #{target.name}.#{inverse} that cannot be found" unless inv
      @inverse = inv
    end

    def validate
      super
      fail "#{entity.name}.#{name} and #{target.name}.#{inverse.name} are not each other's inverse" unless inverse.inverse == self
    end

    def objcTypeName
      "Relationship"
    end

    def objcDeleteRuleEnum
      "ODORelationshipDeleteRule#{delete.capitalize_first}"
    end
    
    def read_only?
      # To-many relationships are implicitly calculated/read-only. The inverse to-one is the editable side.
      calculated || @many
    end
    
    # Would be better to have emitInterface have a way for use to declare properties and pass the class.  Then it could collect those and emit the @class w/o us repeating this logic.
    def add_class_names(names)
      return if self.inherited_from
      if @many
        names << "NSSet"
        names << target_name
      else
        if entity.abstract
          names << entity.instance_class
        else
          names << target.instance_class
       end
      end
    end

    def emitInterface(f)
      attributes = ""
      if !swift_name.nil?
        attributes += " NS_SWIFT_NAME(#{swift_name})"
      end
      attributes += deprecatedAttribute
      if @many
        # Don't emit this relationship if we've already emitted an inherited concrete property for it.
        # Otherwise we want to emit a covariant override at each level of the hierarchy
        if self.inherited_from
          inherited_relationship = self.inherited_from.property_named(self.name)
          return if !inherited_relationship.abstract_target?
        end
        kindof_attribute = abstract_target? ? "__kindof " : ""
        f << "@property (nonatomic, nullable, readonly) NSSet<#{kindof_attribute}#{target_name} *> *#{name}#{attributes};\n"
      else
        if entity.abstract || abstract_target?
          # Hacky; we have abstract self relationships for parent children.  Abstract entities don't have their relationship destinations resolved since they don't point to something real. We can at least declare the type of the to-one as specifically as we know it. Declare it read-only though (with the __kindof qualifier), since we would prefer typechecking of the exact right class for writes.
          fail "Expect abstract entities to be self joins." unless entity.name == target
          f << "@property (nonatomic, nullable, readonly) __kindof #{entity.instance_class} *#{name}#{attributes};\n"
        else
          if read_only?
            read_only_attribute = ", readonly"
          else
            read_only_attribute = ""
          end
          f << "@property (nonatomic, nullable#{read_only_attribute}, strong) #{target.instance_class} *#{name}#{attributes};\n"
       end
      end
    end

    def needsSwiftInterface?
      false
    end

    def emitSwiftInterface(f)
    end

    def emitCreation(f)
      f << "    #{objcClassName} *#{varName} = ODORelationshipCreate(#{property_init_args}, #{objcBool(many)}/*toMany*/, #{objcDeleteRuleEnum});\n"
    end

    def emitBinding(f)
      f << "    ODORelationshipBind(#{varName}, #{entity.varName}, #{target.varName}, #{inverse.varName});\n"
    end

    def target_name
        case target
        when String
          target_entity = entity.model.entity_named(target)
          return target_entity ? target_entity.instance_class : "#{entity.model.name}#{target}"
        when Entity
          return target.instance_class
        else
          fail "Unexpected type for target on relationship #{entity.name}.#{name}"
        end
    end
    
    def abstract_target?
        case target
        when String
          target_entity = entity.model.entity_named(target)
          return target_entity ? target_entity.abstract : true
        when Entity
          target_name = target.instance_class
          return target.abstract
        else
          fail "Unexpected type for target on relationship #{entity.name}.#{name}"
        end
    end
  end
end
