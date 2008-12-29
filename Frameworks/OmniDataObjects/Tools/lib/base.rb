module OmniDataObjects
  class Base
    def objcClassName
      "ODO#{objcTypeName}"
    end
    
    def emitDeclaration(fp)
      fp.h << "extern NSString * const #{keyName};\n"
    end
    
    def emitDefinition(fp)
      fp.m << "NSString * const #{keyName} = @\"#{name}\";\n"
    end
    
    def emit(fp)
      emitDeclaration(fp)
      emitDefinition(fp)
    end
    
    def objcBool(v)
      v ? "YES" : "NO"
    end
  end
end
