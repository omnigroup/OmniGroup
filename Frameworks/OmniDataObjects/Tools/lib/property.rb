module OmniDataObjects
  class Property < Base
    attr_reader :entity, :name, :optional, :transient, :inherited_from, :calculated

    def initialize(entity, name, options = {})
      @entity = entity
      @name = name.to_s
      @optional = options[:optional]
      @transient = options[:transient]
      @inherited_from = options[:inherited_from]
      @calculated = options[:calculated]
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
    
    def emitBinding(fp)
    end
    
    def property_init_args
      "#{keyName}, #{objcBool(optional)}/*optional*/, #{objcBool(transient)}/*transient*/, #{objcGetSel}, #{objcSetSel}"
    end
  end
end
