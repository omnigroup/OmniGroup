// Copyright 2007-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <Availability.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#define OF_LOCK_FILE_AVAILABLE 1
#else
#define OF_LOCK_FILE_AVAILABLE 0
#endif

#if OF_LOCK_FILE_AVAILABLE

extern NSString * const OFLockExistingLockKey;
extern NSString * const OFLockProposedLockKey;
extern NSString * const OFLockLockUnavailableHandlerKey;

@protocol OFLockUnavailableHandler;

typedef NS_OPTIONS(NSUInteger, OFLockFileLockOperationOptions) {
    OFLockFileLockOperationOptionsNone = (0),
    OFLockFileLockOperationOverrideLockOption = (1UL << 1),
    OFLockFileLockOperationAllowRecoveryOption = (1UL << 2), // If OFLockFileLockOperationAllowRecoveryOption, failure to acquire the lock file is treated as a soft error. The NSError instance returned will have the code OFLockUnavailable and a recovery attempter. Otherwise, OFCannotCreateLock is returned.
};

@interface OFLockFile : NSObject

+ (void)setDefaultLockUnavailableHandler:(id <OFLockUnavailableHandler>)handler;
+ (id <OFLockUnavailableHandler>)defaultLockUnavailableHandler;

- (id)initWithURL:(NSURL *)lockFileURL; // The URL of the lock file itself, not the item to be locked.

@property (nonatomic, readonly) NSURL *URL;

- (BOOL)lockWithOptions:(OFLockFileLockOperationOptions)options error:(NSError **)outError;
- (void)unlockIfLocked;

@property (nonatomic, retain) id <OFLockUnavailableHandler> lockUnavailableHandler;

@property (nonatomic, readonly) BOOL invalidated;

@property (nonatomic, readonly) NSString *ownerLogin;
@property (nonatomic, readonly) NSString *ownerName;
@property (nonatomic, readonly) NSString *ownerHost;
@property (nonatomic, readonly) NSNumber *ownerProcessNumber;
@property (nonatomic, readonly) NSString *ownerProcessBundleIdentifier;
@property (nonatomic, readonly) NSDate *ownerLockDate;

@end

#pragma mark -

@protocol OFLockUnavailableHandler <NSObject>

@required
- (BOOL)handleLockUnavailableError:(NSError *)error;
    // Return YES to indicate that the problem was handled.
    // A typical implementation might just present the NSError and let -presentError: handle error recovery as normal.

@optional
- (NSString *)localizedCannotCreateLockErrorReason;
    // Human readable error string to be used for the localized reason for the OFCannotCreateLock error code

@end

#endif
