module OmniDataObjects
  # TODO: Validate the name doesn't start with "ODO".  Make sure metadata table does.
  class Entity < Base
    attr_reader :model, :name, :instance_class, :properties, :abstract, :header_file, :prefetch_order

    def initialize(model, name, options = {})
      @model = model
      @name = name
      @instance_class = options[:instance_class] || "#{model.name}#{name}"
      @properties = []
      @abstract = options[:abstract] || false
      @prefetch_order = options[:prefetch_order]
    end

    def property_named(name)
      properties.find {|p| p.name == name}
    end

    def add_property(p)
      fail "Entity '#{name}' already has a property named '#{p.name}'" if property_named(p.name)
      fail "Adding property to the wrong entity" if p.entity != self
      properties << p
    end

    def process
      STDERR.print "Processing entity #{name}\n" if Options.debug
      properties.sort! {|a,b| a.name <=> b.name}
      properties.each {|p| p.process}
    end

    def validate
      STDERR.print "Validating entity #{name}\n" if Options.debug
      properties.each {|p| p.validate}
      
      primary_keys = properties.select {|p| Attribute === p && p.primary}
      fail "Exactly one primary key expected in #{name}, but #{primary_keys.size} found." if primary_keys.size != 1
    end

    def objcTypeName
      "Entity"
    end
    
    def keyName
      "#{model.name}#{name}#{objcTypeName}Name"
    end
    
    def varName
      "#{name}"
    end
    
    def statementKey(k)
      "@\"#{k.to_s}:#{name}\""
    end
    
    def header_file_name
      "#{instance_class}-Properties.h"
    end

    def header_file(fs)    
      # Put the property definitions and string constants in their own header, assuming the main header written by the developer will import them.
      fs.make_if(header_file_name)
    end
    
    def swift_extension_file_name
      "#{instance_class}-Properties.swift"
    end

    def swift_extension_file(fs)
      fs.make_if(swift_extension_file_name)
    end
    
    def emitDeclaration(fp)
      # All our properties are dynamic, which is the default.  Emit declarations for them.
      class_names = Array.new
      properties.each {|p| p.add_class_names(class_names)}
      class_names.uniq.sort.each {|c|
        fp.h << "@class #{c};\n"
      }
      
      fp.h << "\n@interface #{instance_class} ()\n\n"
      begin
        properties.each {|p|
          p.emitInterface(fp.h)
        }
      end
      fp.h << "\n@end\n"
      fp.h.br
      
      if properties.length > 0
        fp.h << "#define #{instance_class}_DynamicProperties @dynamic #{(properties.map {|p| p.name}).join(", ")}\n\n"
      end
      
      return if abstract # Don't want the global for the entity name
      super
    end

    def emitDefinition(fp)
      return if abstract # Don't want the global for the entity name
      super
    end

    def emitSwiftDefinition(fp)
      swift_properties = Array.new
      properties.each {|p| swift_properties << p if p.needsSwiftInterface? }
      return if swift_properties.count == 0
      fp.swift << "import OmniDataObjects\n\n"
      fp.swift << "public extension #{instance_class} {\n"
      swift_properties.each_with_index {|p, index|
        p.emitSwiftInterface(fp.swift)
        fp.swift << "\n" unless index == swift_properties.count - 1
      }
      fp.swift << "}\n"
    end

    def emitCreation(f)
      f << "    ODOEntity *#{varName} = ODOEntityCreate(#{keyName}, #{statementKey(:I)}, #{statementKey(:U)}, #{statementKey(:D)}, #{statementKey(:PK)},\n"
      f << "    @\"#{instance_class}\",\n"
      
      # All properties
      f << "    [NSArray arrayWithObjects:"
      properties.each {|p| f << "#{p.varName}, " }
      f << "nil],"

      f << "#{prefetch_order || "NSNotFound"}"

      f << ");\n"
    end
    
    def emitBinding(f)
      f << "    ODOEntityBind(#{varName}, model);\n"
    end
  end
end
