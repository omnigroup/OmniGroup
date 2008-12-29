// Copyright 2001-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OFScheduledEvent, OFVersionNumber;
@class NSTask, NSFileHandle, NSData;
@class OSUCheckOperation;

extern NSString *OSUSoftwareUpdateExceptionName;

// 
extern NSString * const OSULicenseTypeUnset;
extern NSString * const OSULicenseTypeNone;
extern NSString * const OSULicenseTypeRegistered;
extern NSString * const OSULicenseTypeRetail;
extern NSString * const OSULicenseTypeBundle;
extern NSString * const OSULicenseTypeTrial;
extern NSString * const OSULicenseTypeExpiring;

@interface OSUChecker : OFObject
{
    OFScheduledEvent *_automaticUpdateEvent;
    
    id _checkTarget;
    SEL _checkAction;
    
    NSString *_licenseType;
    BOOL _initiateCheckOnLicenseTypeChange;
    BOOL _scheduleNextCheckOnLicenseTypeChange;
    
    struct {
        unsigned int shouldCheckAutomatically: 1;
        unsigned int checkOperationInitiatedByUser: 1;
    } _flags;

    struct _OSUSoftwareUpdatePostponementState *_postpone;
    
    OSUCheckOperation *_currentCheckOperation;
}

+ (OSUChecker *)sharedUpdateChecker;

+ (OFVersionNumber *)OSUVersionNumber; // of the framework itself, not the main app
+ (OFVersionNumber *)runningMarketingVersion;

+ (NSArray *)supportedTracksByPermissiveness;
+ (NSString *)applicationTrack;
+ (BOOL)applicationOnReleaseTrack;

- (NSString *)licenseType;
- (void)setLicenseType:(NSString *)licenseType;
- (void)setTarget:(id)anObject;
- (void)setAction:(SEL)aSelector;
- (void)checkSynchronously;
- (NSDictionary *)generateReport;

@end


@interface OSUChecker (SubclassOpportunity)

// Subclasses can provide implementations of this in order to prevent OSUChecker from checking when it shouldn't. -hostAppearsToBeReachable: is called in the main thread; OSUChecker's implementation uses the SystemConfiguration framework to check whether the machine has any routes to the outside world. (We can't explicitly check for a route to omnigroup.com or the user's proxy server, because that would require doing a name lookup; we can't do multithreaded name lookups without the stuff in OmniNetworking, so doing a name lookup might hang the app for a while (up to a few minutes) --- bad!)

- (BOOL)hostAppearsToBeReachable:(NSString *)aHostname;

// Subclassers can override these if they have a need to specify different bundle identifiers, app versions or visible tracks (for test purposes, for instance).
- (NSString *)targetBundleIdentifier;
- (NSString *)targetMarketingVersionStringFromBundleInfo:(NSDictionary *)bundleInfo;
- (NSString *)targetBuildVersionStringFromBundleInfo:(NSDictionary *)bundleInfo;

@end

@interface NSObject (OFSoftwareUpdateTarget)
/* Callback for when we determine there are new versions available -- presumably you want to notify the user of this. */
- (void)newVersionsAvailable:(NSArray *)items; /* NSArray of OSUItem */
@end

