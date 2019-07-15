// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@class NSArray;
@class OSUChecker, OSUCheckOperation, OSUItem;

typedef enum _OSUPrivacyNoticeResult {
    OSUPrivacyNoticeResultOK,
    OSUPrivacyNoticeResultShowPreferences,
} OSUPrivacyNoticeResult;

@protocol OSUCheckerTarget <NSObject>

// The one required method; we must ask for permission before sending anything across the network. "Previous version" here means an older iteration of the software update framework itself (not the app being updated). If this is YES, then the user has previously agreed to send details, but the new version of the OSU framework may send more information.
- (OSUPrivacyNoticeResult)checker:(OSUChecker *)checker runPrivacyNoticePanelHavingSeenPreviousVersion:(BOOL)hasSeenPreviousVersion;

@optional

// Called when the OSUChecker is ready to do checks.
- (void)checkerDidStart:(OSUChecker *)checker;

// Called at the top of -[OSUChecker checkSynchronously], allowing the target to prevent another check from starting.
- (BOOL)checkerShouldStartCheck:(OSUChecker *)checker;

// Called once a check operation is actually started
- (void)checker:(OSUChecker *)checker didStartCheck:(OSUCheckOperation *)op;

// Called when the operation failed with some error (which may or may not be suitable for presenation to the user based on the initiatedByUser property on the operation).
- (void)checker:(OSUChecker *)checker check:(OSUCheckOperation *)op failedWithError:(NSError *)error;

/* Callback for when we determine there are new versions available -- presumably you want to notify the user of this. */
- (void)checker:(OSUChecker *)checker newVersionsAvailable:(NSArray<OSUItem *> *)items /* NSArray of OSUItem */ fromCheck:(OSUCheckOperation *)op;

@end

