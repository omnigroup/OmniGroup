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
      if @many
        return if self.inherited_from
        names << "NSSet"
      else
        if entity.abstract
          names << entity.instance_class
        else
          names << @target.instance_class
       end
      end
    end
    def emitInterface(f)
      if @many
        # To many relationships are all sets and are (currently) read-only.  For now the inverse to-one is the editing point.
        return if self.inherited_from # don't redeclare inherited to-many relationships since they'll have the same definition in the superclass
        f << "@property(readonly) NSSet *#{name};\n"
      else
        if entity.abstract
          # Hacky; we have abstract self relationships for parent children.  Abstract entities don't have their relationship destinations resolved since they don't point to something real. We can at least declare the type of the to-one as specifically as we know it. Declare it read-only though, since we would prefer typechecking of the exact right class for writes.
          fail "Expect abstract entities to be self joins." unless entity.name == target
          f << "@property(readonly) #{entity.instance_class} *#{name};\n"
        else
          if read_only?
            read_only_attribute = ",readonly"
          else
            read_only_attribute = ""
          end
          f << "@property(nonatomic#{read_only_attribute},retain) #{@target.instance_class} *#{name};\n"
       end
      end
    end

    def emitCreation(f)
      f << "    #{objcClassName} *#{varName} = ODORelationshipCreate(#{property_init_args}, #{objcBool(many)}/*toMany*/, #{objcDeleteRuleEnum});\n"
    end

    def emitBinding(f)
      f << "    ODORelationshipBind(#{varName}, #{entity.varName}, #{target.varName}, #{inverse.varName});\n"
    end
  end
end
