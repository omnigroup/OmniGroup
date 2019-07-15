// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

/*
 NSNetService and friends are pretty slow and we have to throttle our updates to avoid annoying mDNSResponder. This is a process-local API-alike for OFNetStateNotifier and OFNetStateRegistration
 */

@interface OFNetStateNotifierMock : NSObject

+ (void)install;

@end
