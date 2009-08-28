module OmniDataObjects
  class Attribute < Property
    attr_reader :type, :default_value, :primary

    def initialize(entity, name, type, options = {})
      super(entity, name, options)
      @type = type
      @default_value = options[:default]
      @primary = options[:primary]
      @value_class = options[:value_class]
    end

    def validate
      super
      fail "Attribute #{entity.name}.#{name} specified a transient or optional primary key" if (primary && (transient || optional))
      # I suppose we could support this with NSCoding, but not needed for now.
      fail "Attribute #{entity.name}.#{name} has unknown value type but isn't transient" if type == :undefined && !transient
    end

    def objcTypeName
      "Attribute"
    end

    def objcTypeEnum
      "ODOAttributeType#{type.to_s.capitalize_first}"
    end

    def objcValueClass
      case type
      when :boolean, :int16, :int32, :int64, :float32, :float64
        "NSNumber"
      when :string
        "NSString"
      when :date
        "NSDate"
      when :data
        "NSData"
      when :undefined
        return @value_class || "NSObject"
      else
        fail "Unknown type name #{type}"
      end
    end

    def objcDefaultValue
      return "nil" if default_value.nil?
      case type
      when :int32
        "[[NSNumber alloc] initWithInt:#{default_value}]"
      when :boolean
        default_value ? "(id)kCFBooleanTrue" : "(id)kCFBooleanFalse"
      else
        fail "Don't know how to generate a default value for type #{:type}"
      end
    end
    
    def add_class_names(names)
      names << objcValueClass
    end
    def emitInterface(f)
      # We don't currently make any pretense at being thread-safe (other that the whole stack being used in a thread).  So, use nonatomic.  Also, all attribute values should be copied on assignment.
      return if self.inherited_from # don't redeclare inherited attributes since they'll have the same definition in the superclass
      f << "@property(nonatomic,copy) #{objcValueClass} *#{name};\n"
    end
    
    def emitCreation(f)
      f << "    #{objcClassName} *#{varName} = ODOAttributeCreate(#{property_init_args}, #{objcTypeEnum}, [#{objcValueClass} class], #{objcDefaultValue}/*default value*/, #{objcBool(primary)}/*primary*/);\n"
    end

    def emitBinding(f)
      f << "    ODOPropertyBind(#{varName}, #{entity.varName});\n"
    end
  end
end
