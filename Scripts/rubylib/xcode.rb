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

# Utility functions imported by Xcode::Project and Xcode::Workspace

require 'pathname'

alias regular_backquote `

module Xcode
  
	def self.read_only_command(cmd)
		# If the 'omni' build system is loaded...
		if Module.const_defined?(:Omni)
			return Omni.read_only_command(cmd)
		else
			return regular_backquote(cmd)
		end
	end
	
  # Pathname.realpath requires the whole path to exist and .realdirpath requires the parent directory to exist (only the last path component can be missing).
  def self.real_relative_path(p)
    fail "Empty path" if p == ""
  
    # This should handle the base case of "/" and "."
    if File.exist?(p)
      Pathname.new(p).realpath.to_s
    else
      real_relative_path(File.dirname(p)) + "/" + File.basename(p)
    end
  end
  
  # Support for checking out workspaces and projects in a shared cache under the control of a calling script
  $CheckoutLocationBlock = nil
  def self.checkout_location_block=(block)
    $CheckoutLocationBlock = block
  end
  def self.checkout_location(path)
    if $CheckoutLocationBlock
      $CheckoutLocationBlock.call(path)
    else
      path
    end
  end
  
  
end

