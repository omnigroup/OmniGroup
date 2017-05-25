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

require 'xcode'
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
  
  class Workspace::PathReference < Struct.new(:path, :project_paths)
  end
  
  class Workspace::Workspace
      
    @@AllowMissing = true
    
    def self.allow_missing=(value)
      @@AllowMissing = value
    end
    
    attr_reader :path, :checkout_location, :root
    attr_reader :autocreate_schemes
    attr_accessor :allow_missing
    
    # The path is the nominal location, while @checkout_location is the real path on disk (possibly a cache)
    def initialize(path, options = {})
      @checkout_location = Pathname.new(Xcode::checkout_location(path)).realpath.to_s
      fail "#{path} is not a directory\n" unless File.directory?(@checkout_location)
      
      @path = Xcode::real_relative_path(path) # Allow missing path here since we might have a different checkout location

      xml_file = @checkout_location + "/contents.xcworkspacedata"
      fail "no contents.xcworkspacedata file in #{@checkout_location}\n" unless File.exist?(xml_file)
      
      doc = REXML::Document.new(File.read(xml_file))
      fail "Unable to read '#{xml_file}'\n" if (doc.nil? || doc.root.nil?)
      
      fail "Expected Workspace element at root" unless doc.root.name == "Workspace"
      
      @allow_missing = @@AllowMissing
      @root = Xcode::Workspace::Group.from_xml(self, doc.root)
      
      @autocreate_schemes = true
      settings_path = @checkout_location + "/xcshareddata/WorkspaceSettings.xcsettings"
      if File.exist?(settings_path)
        settings = Plist::parse_xml(Xcode.read_only_command("plutil -convert xml1 -o - \"#{settings_path}\""))

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
    
    def add_dir_ref(ref_by_dir, path, file_type, project_path)
			
			if file_type == "folder"
				# When copying folders, for example, This is particularly important if we have a file reference in ^/Foo -- we don't want to check out the parent (the entire repository!)
				dir_path = path
			else
	      dir_path = File.dirname(path)
			end
			
      ref = ref_by_dir[dir_path]
      if ref.nil?
        ref = Xcode::Workspace::PathReference.new(dir_path, [project_path])
        ref_by_dir[dir_path] = ref
      else
        ref.project_paths << project_path unless ref.project_paths.index(project_path)
      end
    end
    
    def missing(path)
        if allow_missing
            STDERR.print "--- Skipping missing #{path} (maybe excluded during autobuild)\n"
        else
            fail "The path #{path} is missing!"
        end
    end
    
    # Collects the transitive closure of files referenced by this workspace and any xcodeproj files referenced directly or indirectly
    # This depends upon the referenced projects being checked out, and doesn't consider any branched directories, which would be needed for PostAutoBuildSequences
    # The results are instances of Workspace::PathReference. The reference given won't necessarily contain all the project paths refering to its path or subpaths (usually useful for getting rid of bad references, so you might need to use it iteratively).
    def directory_references
      ref_by_dir = {}
      add_dir_ref(ref_by_dir, path, "xcworkspace", path) # The directory containing this workspace
      
      # TODO: If a group in the workspace has a path set, we should probably include that? But the few places we have that, it points at OmniGroup/Frameworks and we don't need all that.
      project_paths = []
      processed_project_paths = {}
      each_file {|f|
        path = f.absolute_path
        
        if File.extname(path) == ".xcodeproj"
          project_paths << path
        end
      }

      while project_paths.size > 0
        project_path = project_paths.shift
        
        next if processed_project_paths[project_path] # Skip projects that we've seen via another path
        processed_project_paths[project_path] = true
        
        add_dir_ref(ref_by_dir, project_path, "xcodeproj", project_path)

        #STDERR.print "project_path = #{project_path}\n"
        project = Xcode::Project.from_path(project_path)
        if !project
            missing(project_path)
            next
        end

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
            add_dir_ref(ref_by_dir, fullpath, item.fileType, project_path)
          else
            fail "Don't know what to do with #{item} at #{fullpath}\n"
          end
        }
        
        #STDERR.print "project #{project_path}\n"
      end
      
      # Sort directories by size so that we can check if an ancestor is already present
      ordered_dirs = ref_by_dir.keys.sort {|a,b| a.size <=> b.size }
      
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
        #STDERR.print "NOTE: Removing bad reference to #{d}\n"
        unique_dirs.delete(d)
      }
      
      unique_dirs.sort {|a,b| a <=> b }.map {|d|
        ref_by_dir[d]
      }
    end
    
  end
  
end
