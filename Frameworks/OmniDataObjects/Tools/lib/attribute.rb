module OmniDataObjects
  class Attribute < Property
    attr_reader :type, :value_class, :default_value, :primary, :objc_is_getter

    def initialize(entity, name, type, options = {})
      super(entity, name, options)
      @type = type
      @copy = options.key?(:copy) ? options[:copy] : true
      @value_class = options[:value_class]
      @string_enum = options[:string_enum]
      if @string_enum 
          fail("Extensible enums only allowed for string properties") if @type != :string
      end
      @default_value = options[:default]
      @primary = options[:primary]
      @objc_is_getter = options.key?(:objc_is_getter) ? options[:objc_is_getter] : true
    end

    def validate
      super
      fail "Attribute #{entity.name}.#{name} specified a transient or optional primary key" if (primary && (transient || optional))
      # I suppose we could support this with NSCoding, but not needed for now.
      fail "Attribute #{entity.name}.#{name} has unknown value type but isn't transient" if type == :undefined && !transient
      # Required scalar value types must supply a default value in the model
      fail "Attribute #{entity.name}.#{name} is a required scalar value type but doesn't have a default value" if scalarValueType? && default_value.nil?
      # Boolean attributes shouldn't have a prefix of `is`; we'll generate the correct getters and Swift names automatically
      fail "Attribute #{entity.name}.#{name} should not have a name prefix of \is\"." if type == :boolean && name =~ /^_?is[A-Z]/
    end

    def objcTypeName
      "Attribute"
    end

    def objcTypeEnum
      case type
      when :xmldatetime
        "ODOAttributeTypeXMLDateTime"
      else
        "ODOAttributeType#{type.to_s.capitalize_first}"
      end
    end
    
    def customGetter?
      if scalarValueType? && !scalarGetterName.nil?
        true
      else
        false
      end
    end

    def objcGetSel
      if scalarValueType? && !scalarGetterName.nil?
        "@selector(#{scalarGetterName})" 
      else
        "@selector(#{name})"
      end
    end
    
    def objcGetterName
      objcGetSel[/@selector\((.*)\)/,1]
    end
    
    def scalarValueType?
      case type
      when :boolean, :int16, :int32, :int64, :float32, :float64
        !optional
      else
        false
      end
    end

    def optionalScalarValueType?
      case type
      when :boolean, :int16, :int32, :int64, :float32, :float64
        optional
      else
        false
      end
    end

    def scalarGetterName
      if type == :boolean && objc_is_getter
        case name
        # prefixes
        when /^_?(allows|are|contains|has|is|should|use|uses|wants)[A-Z]/
          return nil
        # mid-property name  
        when /[a-z](Allows|Are|Contains|Has|Is|Should|Use|Uses|Wants)[A-Z]/
          return nil
        else
          if name.start_with?("_")
            return "_is#{name[1..-1].capitalize_first}"
          else
            return "is#{name.capitalize_first}"
          end  
        end
      end
      return nil
    end
    
    def swiftNSNumberPropertyName
      case type
      when :boolean
        "boolValue"
      when :int16, :int32, :int64
        type.to_s + "Value"
      when :float32
        "floatValue"
      when :float64
        "doubleValue"
      else
        fail "No NSNumber property for #{entity.name}.#{name} of type #{type}"
      end
    end

    def objcValueClass
      # All this to be forced via value_class; unlikely for most types, but NSData.
      return value_class if value_class
      
      case type
      when :boolean, :int16, :int32, :int64, :float32, :float64
        "NSNumber"
      when :string
        "NSString"
      when :date, :xmldatetime
        "NSDate"
      when :data
        "NSData"
      when :undefined
        "NSObject"
      else
        fail "Unknown type name #{type}"
      end
    end

    def objcValueType
        if @string_enum
            return @string_enum
        else
            return "#{objcValueClass} *"
        end
    end
    
    def objcScalarType
      case type
      when :boolean
        "BOOL"
      when :int16
        "int16_t"
      when :int32
        "int32_t"
      when :int64
        "int64_t"
      when :float32
        "float"
      when :float64
        "double"
      else
        fail "Cannot convert #{type} to scalar type"
      end
    end

    def swiftValueClass
      # All this to be forced via value_class; unlikely for most types, but NSData.
      return value_class if value_class
      
      case type
      when :boolean
        "Bool"
      when :int16
        "Int16"
      when :int32
        "Int32"
      when :int64
        "Int64"
      when :float32
        "Float32"
      when :float64
        "Float64"
      when :string
        "String"
      when :date, :xmldatetime
        "Date"
      when :data
        "Data"
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
      when :int16
        "[[NSNumber alloc] initWithShort:#{default_value}]"
      when :int32
        "[[NSNumber alloc] initWithInt:#{default_value}]"
      when :int64
        "[[NSNumber alloc] initWithLongLong:#{default_value}]"
      when :float32
        "[[NSNumber alloc] initWithFloat:#{default_value}]"
      when :float64
        "[[NSNumber alloc] initWithDouble:#{default_value}]"
      when :boolean
        if !(TrueClass === default_value || FalseClass === default_value)
          fail "The default value for boolean property \"#{name}\" must be either `true` or `false`"
        end
        default_value ? "(id)kCFBooleanTrue" : "(id)kCFBooleanFalse"
      when :string
        "@\"#{default_value}\""
      else
        fail "Don't know how to generate a default value for type #{type}"
      end
    end
    
    def add_class_names(names)
        # Strip lightweight generics or protocol conformance from the objcValueClass
      names << objcValueClass.sub(/<.*>/, '')
    end
    
    def copy?
        @copy
    end
    
    def read_only?
      primary || calculated
    end
    
    def emitInterface(f)
      # We don't currently make any pretense at being thread-safe (other that the whole stack being used in a thread).  So, use nonatomic.  Also, all attribute values should be copied on assignment _if_ they are writable.  Calculated properties are declared to be read-only, but their implementations my redefine the property internally to be writable. We have to still use 'copy' in that case, though, else the compiler signals a storage mechanism conflict when redefining.
      return if self.inherited_from # don't redeclare inherited attributes since they'll have the same definition in the superclass
      
      attributes = ""
      if !swift_name.nil?
        attributes += " NS_SWIFT_NAME(#{swift_name})"
      end
      
      if optionalScalarValueType?
        attributes += " NS_REFINED_FOR_SWIFT"
      end

      attributes += deprecatedAttribute

      if scalarValueType?
          additional_attributes = ""

          if read_only?
            additional_attributes += ", readonly"
          end
          
          if customGetter?
            additional_attributes += ", getter=#{objcGetterName}"
          end

          f << "@property (nonatomic#{additional_attributes}) #{objcScalarType} #{name}#{attributes};\n"
      else
          additional_attributes = ""

          if optional || default_value.nil?
            additional_attributes += ", nullable"
          end
            
          if copy?
            additional_attributes += ", copy"
          else
            additional_attributes += ", strong"
          end
      
          if read_only?
            additional_attributes += ", readonly"
          end
      
          if customGetter?
            additional_attributes += ", getter=#{objcGetterName}"
          end

          f << "@property (nonatomic#{additional_attributes}) #{objcValueType} #{name}#{attributes};\n"
      end
    end
    
    def needsSwiftInterface?
      optionalScalarValueType?
    end
    
    def emitSwiftInterface(f)
      return unless needsSwiftInterface?
      accessors = <<EOS
    var #{name}: #{swiftValueClass}? {
        get {
            return __#{name}?.#{swiftNSNumberPropertyName}
        }
        set {
            if let value = newValue {
              __#{name} = NSNumber(value: value)
            } else {
              __#{name} = nil
            }
        }
    }
EOS
      attribute = swiftAvailableAttribute
      f << "    #{attribute}\n" if !attribute.empty?
      f << accessors
    end
    
    def emitCreation(f)
      f << "    #{objcClassName} *#{varName} = ODOAttributeCreate(#{property_init_args}, #{objcTypeEnum}, [#{objcValueClass} class], #{objcDefaultValue}/*default value*/, #{objcBool(primary)}/*primary*/);\n"
    end

    def emitBinding(f)
      f << "    ODOPropertyBind(#{varName}, #{entity.varName});\n"
    end
  end
end
