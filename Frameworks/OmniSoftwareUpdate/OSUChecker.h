// Copyright 2001-2008,2010, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFNetReachability.h>

@class OFVersionNumber;
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
@class OFScheduledEvent;
#else
@class NSTimer;
#endif
@class OSUCheckOperation;
@protocol OSUCheckerTarget;

// 
extern NSString * const OSULicenseTypeUnset;
extern NSString * const OSULicenseTypeNone;
extern NSString * const OSULicenseTypeRegistered;
extern NSString * const OSULicenseTypeRetail;
extern NSString * const OSULicenseTypeBundle;
extern NSString * const OSULicenseTypeTrial;
extern NSString * const OSULicenseTypeExpiring;
extern NSString * const OSULicenseTypeAppStore;

#define OSUCheckerCheckInProgressBinding (@"checkInProgress")
#define OSUCheckerLicenseTypeBinding (@"licenseType")

@interface OSUChecker : OFObject <OFNetReachabilityDelegate>
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    NSTimer *_automaticUpdateTimer;
#else
    OFScheduledEvent *_automaticUpdateEvent;
#endif
    
    id <OSUCheckerTarget> _checkTarget;
    
    NSString *_licenseType;
    
    struct {
        unsigned int shouldCheckAutomatically: 1;
        unsigned int initiateCheckOnLicenseTypeChange: 1;
        unsigned int scheduleNextCheckOnLicenseTypeChange: 1;
    } _flags;
    
    OFNetReachability *_netReachability;
    
    OSUCheckOperation *_currentCheckOperation;
    
    // Track info updates
    NSURLConnection *_refreshingTrackInfo;
    NSMutableData *_refreshingTrackData;    
}

+ (OSUChecker *)sharedUpdateChecker;

// Called automatically on the Mac via OFController, but on iOS we start/shutdown manually.
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (void)startWithTarget:(id <OSUCheckerTarget>)target;
+ (void)shutdown;
#endif

+ (OFVersionNumber *)OSUVersionNumber;          // of the framework itself, not the main app

- (NSString *)licenseType;
- (void)setLicenseType:(NSString *)licenseType;
- (BOOL)checkSynchronously;
- (NSDictionary *)generateReport;

@property(readonly) BOOL checkInProgress;

#pragma mark Subclass opportunities

// Information about the current application (used to determine whether another version is newer / applicable)
// Subclassers can override these if they have a need to specify different bundle identifiers, app versions or visible tracks (for test purposes, for instance).
- (OFVersionNumber *)applicationMarketingVersion;    // User-readable version number
- (NSString *)applicationIdentifier;                 // Unique identifier for this application (Apple bundle identifier string)
- (NSString *)applicationEngineeringVersion;         // Reliable, easy-to-compare version number
- (NSString *)applicationTrack;                      // Release/update track of the current application (beta, final, etc.)
- (BOOL)applicationOnReleaseTrack;

@end
