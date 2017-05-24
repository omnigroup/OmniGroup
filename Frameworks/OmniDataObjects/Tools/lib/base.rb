module OmniDataObjects
  class Base
    def objcClassName
      "ODO#{objcTypeName}"
    end
    
    def emitDeclaration(fp)
      fp.h << "extern NSString * const #{keyName}#{deprecatedAttribute};\n"
    end
    
    def emitDefinition(fp)
      fp.m << "NSString * const #{keyName} = @\"#{name}\";\n"
    end
    
    def emitSwiftDefinition(fp)
      # Nothing
    end
    
    def emit(fp)
      emitDeclaration(fp)
      emitDefinition(fp)
      emitSwiftDefinition(fp)
    end
    
    def objcBool(v)
      v ? "YES" : "NO"
    end
    
    def deprecatedAttribute
      return ""
    end
  end
end
