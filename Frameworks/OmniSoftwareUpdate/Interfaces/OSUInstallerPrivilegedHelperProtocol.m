// Copyright 2013-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUInstallerPrivilegedHelperProtocol.h"

#import <Foundation/NSString.h>

// We write a new version of the tool for each protocol update so that we don't need to try to uninstall the tool to downgrade to an older protocol version, which doesn't work well and uses deprecate SMJob* functions See <bug:///113413>

#if !defined(OSUInstallerPrivilegedHelperIdentifier)
#error OSUInstallerPrivilegedHelperIdentifier should be defined by the project
#endif

#define _OSUInstallerPrivilegedHelperJobLabel_(ident) @#ident
#define _OSUInstallerPrivilegedHelperJobLabel(ident) _OSUInstallerPrivilegedHelperJobLabel_(ident)
NSString * const OSUInstallerPrivilegedHelperJobLabel = _OSUInstallerPrivilegedHelperJobLabel(OSUInstallerPrivilegedHelperIdentifier);
