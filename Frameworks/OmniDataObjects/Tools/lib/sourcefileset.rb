module OmniDataObjects
  class SourceFileSet
    attr_reader :files, :base_dir
    def initialize(base_dir = nil)
      @base_dir = base_dir
      @files = {}
    end
    
    def make(name)
      fail "An output file already exists with the name '#{name}'" if files[name]
      files[name] = SourceFile.new(name)
    end
    
    def make_if(name)
      make(name) if files[name].nil?
      files[name]
    end
    
    def pair(name)
      SourceFilePair.new(make("#{name}.h"), make("#{name}.m"))
    end
    
    def write
      files.each {|k,v| v.write(base_dir)}
    end
  end
end
