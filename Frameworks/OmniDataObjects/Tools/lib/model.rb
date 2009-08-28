module OmniDataObjects
  class Model < Base
    attr_reader :name, :entities
    def initialize(name, options = {})
      @name = name
      @entities = []
      @handled_inherits = {}
      @ordered_inherits = []
      @on_load = options[:on_load] # Should be a zero argument function.  This gets called before the model creation function returns, and can re-entrantly call the model creation function to get the model that is done being created, if it needs it.
      @imports = []
      @framework_name = options[:framework_name] # if set, automatically the generated import for the model creation header will be relative to this framework name
    end

    def entity_named(name)
      entities.find {|e| e.name == name}
    end
    def add_entity(e)
      fail "Duplicate entity name #{name}" if entity_named(e.name)
      fail "Registered entities shouldn't be abstract" if e.abstract
      @entities << e
    end
    def add_import(i)
      @imports << i
    end
    
    def add_inherit(k)
      return @handled_inherits[k] if @handled_inherits[k]
      entity_name = k.to_s.underscore_to_camel_case
      STDERR.print "Handling inherit #{k} as #{entity_name}\n" if Options.debug
            
      # Create the abstract entity via the DSL again and invoke the key on itself to add abstract copies of the properties
      i = entity entity_name, :abstract => true do |e|
        e.send(k)
      end
      @handled_inherits[k] = i
      @ordered_inherits << i
      i
    end
    
    def process
      # Relationships start life with their #target and #inverse being strings
      STDERR.print "Processing model #{name}\n" if Options.debug
      entities.sort! {|a,b| a.name <=> b.name}
      entities.each {|e| e.process}
    end
    def validate
      STDERR.print "Validating model #{name}\n" if Options.debug
      entities.each {|e| e.validate}
    end
    
    def objcTypeName
      "Model"
    end

    def emitDeclaration(fp)
      # Nothing
    end
    
    def emitDefinition(fp)
      # Nothing
    end
    
    def entity_pair(e,fs,fp)
      SourceFilePair.new(e.header_file(fs), fp.m) # Direct the interface for each entity to its own file, but the constants to the global model source file.
    end
    
    def emit
      fs = SourceFileSet.new(Options.model_output_directory)
      fp = fs.pair("#{name}Model")
      
      if @framework_name
        fp.m << "#import <#{@framework_name}/#{fp.h.name}>\n"
      else
        fp.m << "#import \"#{fp.h.name}\"\n"
      end

      fp.m << "#import <OmniDataObjects/ODOModel-Creation.h>\n"
      fp.m.br

      fp.m << "#import <Foundation/NSValue.h>\n"
      fp.m << "#import <Foundation/NSString.h>\n"
      fp.m << "#import <Foundation/NSData.h>\n"
      fp.m << "#import <Foundation/NSDate.h>\n\n"
      fp.m.br

      @imports.each {|i|
        fp.m << "#import #{i}\n"
      }
      super(fp)
      fp.br
      
      # Emit variables and property definitions for the inherited entities.  These only have property names (which are shared across all entities inheriting from them).  There is no entity name variable.
      @ordered_inherits.each {|e|
        efp = entity_pair(e,fs,fp)
        e.emit(efp)
        efp.br
        e.properties.each {|p|
          next if p.inherited_from
          p.emit(efp)
        }
      }
      
      # Emit variables for the real entities; skipping those that are from the inherited entities
      entities.each {|e|
        efp = entity_pair(e,fs,fp)
        efp.br
        e.emit(efp)
        efp.br
        e.properties.each {|p|
          next if p.inherited_from
          p.emit(efp)
        }
      }
      
      func = "#{name}Model"
      fp.br

      fp.h << "@class ODOModel;\n"
      fp.h << "extern ODOModel *#{func}(void);\n"

      # Disable clang scan-build in the model creation function.  We allocate a bunch of stuff and don't bother releasing it since we intend for it to stick around anyway.
      fp.m << "#ifdef __clang__\n"
      fp.m << "static void DisableAnalysis(void) __attribute__((analyzer_noreturn));\n"
      fp.m << "#endif\n"
      fp.m << "static void DisableAnalysis(void) {}\n\n"
      
      fp.m << "ODOModel * #{func}(void)\n{\n"
      fp.m << "    DisableAnalysis();\n\n"
      fp.m << "    static ODOModel *model = nil;\n"
      fp.m << "    if (model) return model;\n\n"
      
      begin
        entities.each {|e|
          e.properties.each {|p| p.emitCreation(fp.m)}
          e.emitCreation(fp.m)
          fp.m.br
        }

        fp.m << "    model = ODOModelCreate(@\"#{name}\", [NSArray arrayWithObjects:"
        entities.each {|e| fp.m << "#{e.varName}, "}
        fp.m << "nil]);\n"

        entities.each {|e|
          e.properties.each {|p| p.emitBinding(fp.m)}
          e.emitBinding(fp.m)
          fp.m.br
        }
        
        fp.m << "    ODOModelFinalize(model);\n"
        
        # This is called late enough that the on load hook can call the model generating function again and get the fully created model.
        fp.m << "    #{@on_load}();\n" if @on_load
      end
      fp.m << "    return model;\n"
      fp.m << "}\n"
      
      fs.write
    end
  end
end
