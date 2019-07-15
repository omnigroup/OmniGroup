// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONHost.h>

@interface ONHost ()
+ (void)_raiseExceptionForHostErrorNumber:(int)hostErrorNumber hostname:(NSString *)hostname;
+ (NSException *)_exceptionForExtendedHostErrorNumber:(int)eaiError hostname:(NSString *)name;

- _initWithHostname:(NSString *)aHostname knownAddress:(ONHostAddress *)anAddress;

- (BOOL)isExpired;

- (void)_lookupHostInfoUsingGetaddrinfo;

@end
