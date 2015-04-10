#!/usr/bin/ruby
#
# Copyright 2015 Omni Development, Inc. All rights reserved.
#
# This software may only be used and reproduced according to the
# terms in the file OmniSourceLicense.html, which should be
# distributed with this project and can also be found at
# <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
#
# $Id$

# Very minimal class for getting informtion out of an Xcode xcworkspace file

require 'pathname'
require 'rexml/document'

require 'xcodeproj'

gem_path = Pathname.new(File.dirname(__FILE__) + "/plist-3.1.0/lib").realpath.to_s
$: << gem_path
require 'plist'

module Xcode
  module Workspace
  end
  
  class Workspace::Item
    attr_reader :parent, :location
    
    def initialize(parent, location)
      @parent = parent
      @location = location.dup
      @absolute_path = nil
    end
    
    def absolute_path
      return @absolute_path if @absolute_path # Cached result
      
      divider_position = location.index(":")
      fail "No divider in file location \"#{location}\"" unless divider_position
      
      type = location[0..divider_position]
      path = location[(divider_position+1)..-1]
      
      case type
      when "group:"
        parent_path = @parent.group_path
        @absolute_path = (Pathname.new(parent_path) + path).cleanpath.to_s
      else
        fail "Unrecognized location type \"#{type}\""
      end
      
      return @absolute_path
    end
    
  end
  
  class Workspace::Group < Workspace::Item
    attr_reader :items
    
    def self.from_xml(parent, element)
      fail "Wrong kind of element #{element}" unless (element.name == "Group" || element.name == "Workspace")
      
      items = []
      element.elements.each {|child_element|
        case child_element.name
        when "Group"
          items << from_xml(parent, child_element)
        when "FileRef"
          items << Xcode::Workspace::File.from_xml(parent, child_element)
        else
          fail "Unknown element type \"#{element.name}\""
        end
      }
      
      if element.name == "Workspace"
        location = File.dirname(parent.path)
        name = "Workspace"
      else
        location = element.attributes['location']
        name = element.attributes['name']
        fail "No location specified in #{element}" unless location
      end
      
      return new(parent, location, name, items)
    end

    def initialize(parent, location, name, items)
      super(parent, location)
      @parent = parent
      @location = location.dup
      @items = items.dup
    end
    
    def each_file(&block)
      items.each {|i| i.each_file(&block)}
    end
       
    def group_path
      absolute_path
    end 
  end
  
  class Workspace::File < Workspace::Item
    def self.from_xml(parent, element)
      location = element.attributes['location']
      fail "No location specified in #{element}" unless location
      
      new(parent, location)
    end
    
    def each_file(&block)
      block.call(self)
    end
  end
  
  class Workspace::Workspace
    attr_reader :path, :root
    attr_reader :autocreate_schemes
    
    def initialize(path)
      @path = Pathname.new(path).realpath.to_s
      fail "#{path} is not a directory\n" unless File.directory?(@path)

      xml_file = path + "/contents.xcworkspacedata"
      fail "no contents.xcworkspacedata file in #{path}\n" unless File.exist?(xml_file)
      
      doc = REXML::Document.new(File.read(xml_file))
      fail "Unable to read '#{xml_file}'\n" if (doc.nil? || doc.root.nil?)
      
      fail "Expected Workspace element at root" unless doc.root.name == "Workspace"
      
      @root = Xcode::Workspace::Group.from_xml(self, doc.root)
      
      @autocreate_schemes = true
      settings_path = @path + "/xcshareddata/WorkspaceSettings.xcsettings"
      if File.exist?(settings_path)
        settings = Plist::parse_xml(`plutil -convert xml1 -o - "#{settings_path}"`)

        # Can't check if the value is true, since explicit false will be written too.
        if settings.has_key?('IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded')
          @autocreate_schemes = settings['IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded']
        end
      end
      
    end
    
    def each_file(&block)
      root.each_file(&block)
    end
    
    def group_path
      File.dirname(path)
    end
    
    # Collects the transitive closure of files referenced by this workspace and any xcodeproj files referenced directly or indirectly
    # This depends upon the referenced projects being checked out, and doesn't consider any branched directories, which would be needed for PostAutoBuildSequences
    def referenced_directories
      dirs = {}
      dirs[File.dirname(path)] = true # The directory containing this workspace
      
      # TODO: If a group in the workspace has a path set, we should probably include that? But the few places we have that, it points at OmniGroup/Frameworks and we don't need all that.
      project_paths = []
      processed_project_paths = {}
      each_file {|f|
        path = f.absolute_path
        dirs[File.dirname(path)] = true # The directory containing every directly referenced file
        
        if File.extname(path) == ".xcodeproj"
          project_paths << path
        end
      }

      while project_paths.size > 0
        project_path = project_paths.shift
        
        next if processed_project_paths[project_path] # Skip projects that we've seen via another path
        processed_project_paths[project_path] = true
        
        dirs[File.dirname(project_path)] = true # The directory containing every project

        #STDERR.print "project_path = #{project_path}\n"
        project = Xcode::Project.new(project_path)
        project.each_item {|item|
          fullpath = project.resolvepath(item.identifier, false)
          #STDERR.print "item #{item} #{item.identifier} #{item.dict} #{fullpath}\n"
          next if fullpath.nil?
          next if fullpath.index('$') == 0 # Skip items that are relative to $SDKROOT, etc.
          
          if File.extname(fullpath) == ".xcodeproj"
            project_paths << fullpath
            next
          end

          case item
          when Xcode::PBXGroup, Xcode::PBXVariantGroup
            # We don't include anything directly for groups since (for example, we might have a reference to OmniGroup/Frameworks)
          when Xcode::PBXFileReference
            # TODO: If this is a copy-the-folder reference, we only need the folder.
            dirs[File.dirname(fullpath)] = true
          else
            fail "Don't know what to do with #{item} at #{fullpath}\n"
          end
        }
        
        #STDERR.print "project #{project_path}\n"
      end
      
      # Sort directories by size so that we can check if an ancestor is already present
      ordered_dirs = dirs.keys.sort {|a,b| a.size <=> b.size }
      
      unique_dirs = []
      ordered_dirs.each {|d|
        next if unique_dirs.detect {|parent| d.index(parent+"/") == 0 } # Skip if there is something already added that is a prefix
        unique_dirs << d
      }
      
      # Remove directories that shouldn't be included (references in the project need fixing)
      bad_paths = unique_dirs.select {|d|
        d.index("/usr/lib") == 0 || d.index("/System") == 0 || d.index("/Library") == 0
      }
      bad_paths.each {|d|
        STDERR.print "NOTE: Removing bad reference to #{d}\n"
        unique_dirs.delete(d)
      }
      
      unique_dirs.sort {|a,b| a <=> b }
    end
    
  end
  
end
