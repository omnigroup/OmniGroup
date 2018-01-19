module OmniDataObjects
  class Property < Base
      attr_reader :entity, :name, :defineWithName, :getter, :optional, :transient, :inherited_from, :calculated, :swift_name, :deprecated, :deprecated_msg

    def initialize(entity, name, options = {})
      @entity = entity
      @name = name.to_s
      @defineWithName = options[:define]
      @optional = options[:optional]
      @transient = options[:transient]
      @inherited_from = options[:inherited_from]
      @calculated = options[:calculated]
      @swift_name = options[:swift_name]
      case options[:deprecated]
      when TrueClass, FalseClass
        @deprecated = options[:deprecated]
      when String
        @deprecated = true
        @deprecated_msg = options[:deprecated]
      else
        @deprecated = false
        @deprecated_msg = ""
      end
      fail "inherited_from must be an entity" if inherited_from && !(Entity === inherited_from)
    end

    def process
      STDERR.print "Processing #{entity.name}.#{name}\n" if Options.debug
    end

    def validate
      STDERR.print "Validating #{entity.name}.#{name}\n" if Options.debug
      fail "Name must be non-empty" if name.size == 0
    end
    
    # Two properties that have the same key should share the same key name variable
    def keyName
      e = inherited_from || entity
      "#{e.model.name}#{e.name}#{name.capitalize_first}"
    end
    
    # ... but they need to be instantiated as seperate properties w/in their repsective concrete entities
    def varName
      "#{entity.name}_#{name}"
    end
    
    def objcGetSel
      "@selector(#{name})"
    end
    
    def objcSetSel
      return "NULL" if read_only?
      "@selector(set#{name.capitalize_first}:)"
    end
    
    def emitDeclaration(fp)
        # Constant strings get distinct pointers across framework boundaries, which can make -propertyNamed: slower. This allows a property that re-uses a well-known name from another framework us its global instead of making a new constant string.
        if defineWithName
            fp.h << "#define #{keyName} #{defineWithName}\n"
        else
            super
        end
    end
    
    def emitDefinition(fp)
        return if defineWithName
        super
    end
    
    def emitBinding(fp)
    end
    
    def property_init_args
      "#{keyName}, #{objcBool(optional)}/*optional*/, #{objcBool(transient)}/*transient*/, #{objcGetSel}, #{objcSetSel}"
    end
    
    def deprecatedAttribute
      if deprecated
        if !deprecated_msg.nil? && !deprecated_msg.empty?
          return " DEPRECATED_MSG_ATTRIBUTE(\"#{deprecated_msg}\")"
        else
          return " DEPRECATED_ATTRIBUTE"
        end
      else
        return ""      
      end
    end
    
    def swiftAvailableAttribute
      if deprecated
        if !deprecated_msg.nil? && !deprecated_msg.empty?
          return "@available(*, deprecated, message: \"#{deprecated_msg}\")"
        else
          return "@available(*, deprecated)"
        end
      else
        return ""      
      end
    end
  end
end
