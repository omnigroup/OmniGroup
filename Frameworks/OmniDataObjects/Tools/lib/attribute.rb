module OmniDataObjects
  class Attribute < Property
    attr_reader :type, :value_class, :default_value, :primary

    def initialize(entity, name, type, options = {})
      super(entity, name, options)
      @type = type
      @value_class = options[:value_class]
      @default_value = options[:default]
      @primary = options[:primary]
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
      # All this to be forced via value_class; unlikely for most types, but NSData.
      return value_class if value_class
      
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
        "NSObject"
      else
        fail "Unknown type name #{type}"
      end
    end

    def objcDefaultValue
      return "nil" if default_value.nil?
      
      # If there is a custom class, default_value can be an atom to send it a class method.
      if value_class && Symbol === default_value
        return "[#{value_class} #{default_value.to_s}]"
      end
      
      case type
      when :int32
        "[[NSNumber alloc] initWithInt:#{default_value}]"
      when :boolean
        default_value ? "(id)kCFBooleanTrue" : "(id)kCFBooleanFalse"
      else
        fail "Don't know how to generate a default value for type #{type}"
      end
    end
    
    def add_class_names(names)
      names << objcValueClass
    end
    
    def read_only?
      primary || calculated
    end
    
    def emitInterface(f)
      # We don't currently make any pretense at being thread-safe (other that the whole stack being used in a thread).  So, use nonatomic.  Also, all attribute values should be copied on assignment _if_ they are writable.  Calculated properties are declared to be read-only, but their implementations my redefine the property internally to be writable. We have to still use 'copy' in that case, though, else the compiler signals a storage mechanism conflict when redefining.
      return if self.inherited_from # don't redeclare inherited attributes since they'll have the same definition in the superclass
      
      if read_only?
        read_only_attribute = ",readonly"
      else
        read_only_attribute = ""
      end
      
      f << "@property(nonatomic,copy#{read_only_attribute}) #{objcValueClass} *#{name};\n"
    end
    
    def emitCreation(f)
      f << "    #{objcClassName} *#{varName} = ODOAttributeCreate(#{property_init_args}, #{objcTypeEnum}, [#{objcValueClass} class], #{objcDefaultValue}/*default value*/, #{objcBool(primary)}/*primary*/);\n"
    end

    def emitBinding(f)
      f << "    ODOPropertyBind(#{varName}, #{entity.varName});\n"
    end
  end
end
