// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "ONHost.h"

// If none of the options above are defined, ONHost will use the ONGetHostByName tool to perform hostname lookups in a separate task.

@interface ONHost (ONInternalAPI)
+ (void)_raiseExceptionForHostErrorNumber:(int)hostErrorNumber hostname:(NSString *)hostname;
+ (NSException *)_exceptionForExtendedHostErrorNumber:(int)eaiError hostname:(NSString *)name;

- _initWithHostname:(NSString *)aHostname knownAddress:(ONHostAddress *)anAddress;

- (BOOL)isExpired;

- (void)_lookupHostInfoByPipe;
- (void)_lookupHostInfoUsingGetaddrinfo;

@end
