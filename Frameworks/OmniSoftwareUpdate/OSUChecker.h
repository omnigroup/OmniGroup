// Copyright 2001-2008, 2010 Omni Development, Inc.  All rights reserved.
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

#define OSUCheckerCheckInProgressBinding (@"checkInProgress")

@interface OSUChecker : OFObject
{
    OFScheduledEvent *_automaticUpdateEvent;
    
    id _checkTarget;
    
    NSString *_licenseType;
    
    struct {
        unsigned int shouldCheckAutomatically: 1;
        unsigned int initiateCheckOnLicenseTypeChange: 1;
        unsigned int scheduleNextCheckOnLicenseTypeChange: 1;
    } _flags;
    
    struct _OSUSoftwareUpdatePostponementState *_postpone;
    
    OSUCheckOperation *_currentCheckOperation;
}

+ (OSUChecker *)sharedUpdateChecker;

+ (OFVersionNumber *)OSUVersionNumber;          // of the framework itself, not the main app
+ (NSArray *)supportedTracksByPermissiveness;   

- (NSString *)licenseType;
- (void)setLicenseType:(NSString *)licenseType;
- (void)setTarget:(id)anObject;
- (void)checkSynchronously;
- (NSDictionary *)generateReport;

@property(readonly) BOOL checkInProgress;

#pragma mark Subclass opportunities

// Subclasses can provide implementations of this in order to prevent OSUChecker from checking when it shouldn't. -hostAppearsToBeReachable: is called in the main thread; OSUChecker's implementation uses the SystemConfiguration framework to check whether the machine has any routes to the outside world. (We can't explicitly check for a route to omnigroup.com or the user's proxy server, because that would require doing a name lookup; we can't do multithreaded name lookups without the stuff in OmniNetworking, so doing a name lookup might hang the app for a while (up to a few minutes) --- bad!)

// - (BOOL)hostAppearsToBeReachable:(NSString *)aHostname;

// Information about the current application (used to determine whether another version is newer / applicable)
// Subclassers can override these if they have a need to specify different bundle identifiers, app versions or visible tracks (for test purposes, for instance).
- (OFVersionNumber *)applicationMarketingVersion;    // User-readable version number
- (NSString *)applicationIdentifier;                 // Unique identifier for this application (Apple bundle identifier string)
- (NSString *)applicationEngineeringVersion;         // Reliable, easy-to-compare version number
- (NSString *)applicationTrack;                      // Release/update tracks we're on (beta, final, etc.)
- (BOOL)applicationOnReleaseTrack;

@end

@interface NSObject (OFSoftwareUpdateTarget)
/* Callback for when we determine there are new versions available -- presumably you want to notify the user of this. */
- (void)newVersionsAvailable:(NSArray *)items /* NSArray of OSUItem */ fromCheck:(OSUCheckOperation *)op;
@end

