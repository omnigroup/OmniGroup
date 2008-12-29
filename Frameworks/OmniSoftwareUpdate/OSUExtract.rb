#!/usr/bin/ruby

# NSFileManager and hdiutil don't agree with each other (Radar 5468824: hdiutil attach can confuse NSFileManager)
# Copy a single application from the mount point to the temporary location
require 'getoptlong'

@@Verbose = false
@@MountPoint = nil
@@TemporaryPath = nil

options = [
  [ "--verbose", "-v", GetoptLong::NO_ARGUMENT ],
  [ "--mount-point", "-M", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--temporary-path", "-T", GetoptLong::REQUIRED_ARGUMENT ],
]

GetoptLong.new(*options).each do |option, argument|
  case option
    when "--verbose"; @@Verbose = argument
    when "--mount-point"; @@MountPoint = argument
    when "--temporary-path"; @@TemporaryPath = argument
    else fail "Unrecognized option '#{option}'"
    end
end
fail "Mount point not specified" if @@MountPoint.nil?
fail "Temporary path not specified" if @@TemporaryPath.nil?

fail "#{@@TemporaryPath} already exists!" if File.exists?(@@TemporaryPath) # The temporary path must not exist, so that ditto has a clean slate

# Look for a single .app in the mount point
apps = Dir.glob("#{@@MountPoint}/*.app")
fail "Expected a single application in #{@@MountPoint}, but found none." if apps.size == 0
fail "Expected a single application in #{@@MountPoint}, but found #{apps.join(', ')}." if apps.size != 1
@@SourceApp = apps[0]

# Clone the application to the temporary path.  This should not exist yet (and should be in Temporary Items on the same filesystem).
STDERR.print "Copying #{@@SourceApp} to #{@@TemporaryPath}...\n" if @@Verbose
ditto_output = `/usr/bin/ditto '#{@@SourceApp}' '#{@@TemporaryPath}' 2>&1`
fail "Ditto failed with code #{$?} -- #{ditto_output}" if $? != 0
