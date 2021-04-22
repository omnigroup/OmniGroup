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

end

