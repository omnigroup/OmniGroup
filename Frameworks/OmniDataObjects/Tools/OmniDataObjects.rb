#!/usr/bin/ruby

$: << Pathname.new(File.dirname(__FILE__)).realpath

module OmniDataObjects
  class Options
    @@Debug=false
    def self.debug
      @@Debug
    end
    def self.debug=(opt)
      @@Debug=opt
    end
    
    @@ModelOutputDirectory=nil
    def self.model_output_directory
      @@ModelOutputDirectory
    end
    def self.model_output_directory=(d)
      @@ModelOutputDirectory=d
    end

  end
end

class String
  # String#capitalize lowercases all the non-first characters too.  This doesn't work for camelCase.
  def capitalize_first
    str = dup
    str[0..0] = str[0..0].capitalize
    str
  end
  
  def underscore_to_camel_case
    str = capitalize_first
    while pos = (str =~ /_./)
      str[pos..pos+1] = str[pos+1..pos+1].capitalize
    end
    str
  end
end

# Base ruby changes
require 'lib/string_extensions'

# Utilities for writing derived files
require 'lib/sourcefileset'
require 'lib/sourcefilepair'
require 'lib/sourcefile'

# Model classes
require 'lib/base'
require 'lib/model'
require 'lib/entity'
require 'lib/property'
require 'lib/attribute'
require 'lib/relationship'

# Front end
require 'lib/dsl'
