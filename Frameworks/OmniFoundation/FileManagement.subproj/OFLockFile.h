// Copyright 2007-2013 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <Availability.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#define OF_LOCK_FILE_AVAILABLE 1
#else
#define OF_LOCK_FILE_AVAILABLE 0
#endif

#if OF_LOCK_FILE_AVAILABLE
@interface OFLockFile : NSObject

- (id)initWithURL:(NSURL *)lockFileURL; // The URL of the lock file itself, not the item to be locked.

@property (nonatomic, readonly) NSURL *URL;

- (BOOL)lockOverridingExistingLock:(BOOL)override error:(NSError **)outError;
- (void)unlockIfLocked;

@property (nonatomic, readonly) BOOL invalidated;

@property (nonatomic, readonly) NSString *ownerLogin;
@property (nonatomic, readonly) NSString *ownerName;
@property (nonatomic, readonly) NSString *ownerHost;
@property (nonatomic, readonly) NSNumber *ownerProcessNumber;
@property (nonatomic, readonly) NSString *ownerProcessBundleIdentifier;
@property (nonatomic, readonly) NSDate *ownerLockDate;

@end
#endif
