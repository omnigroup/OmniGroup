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
    
    def emitInterface(f)
      # Relationships are all to-many sets and are (currently) read-only.  For now the inverse to-one is the editing point.
      f << "@property(readonly) NSSet *#{name};\n"
    end

    def emitCreation(f)
      f << "    #{objcClassName} *#{varName} = ODORelationshipCreate(#{property_init_args}, #{objcBool(many)}/*toMany*/, #{objcDeleteRuleEnum});\n"
    end

    def emitBinding(f)
      f << "    ODORelationshipBind(#{varName}, #{entity.varName}, #{target.varName}, #{inverse.varName});\n"
    end
  end
end
