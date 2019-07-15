// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <OmniSoftwareUpdate/OSUCheckerTarget.h>

@class NSURL, NSError;
@class NSWindow;
@class OSUItem;

extern NSString * const OSUReleaseDisplayVersionKey;
extern NSString * const OSUReleaseDownloadPageKey;
extern NSString * const OSUReleaseEarliestCompatibleLicenseKey;
extern NSString * const OSUReleaseRequiredOSVersionKey;
extern NSString * const OSUReleaseVersionKey;
extern NSString * const OSUReleaseSpecialNotesKey;
extern NSString * const OSUReleaseMajorSummaryKey;
extern NSString * const OSUReleaseMinorSummaryKey;
extern NSString * const OSUReleaseApplicationSummaryKey;

@interface OSUController : NSObject <OSUCheckerTarget>

// API
+ (OSUController *)sharedController;
+ (void)checkSynchronouslyWithUIAttachedToWindow:(NSWindow *)aWindow;

- (BOOL)beginDownloadAndInstallFromPackageAtURL:(NSURL *)packageURL item:(OSUItem *)item error:(NSError **)outError;

@end
