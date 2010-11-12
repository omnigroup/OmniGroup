// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISoftwareUpdateController.h"

#if OUI_SOFTWARE_UPDATE_CHECK

#import <OmniFoundation/OFPreference.h>
#import <OmniSoftwareUpdate/OSUChecker.h>
#import <OmniSoftwareUpdate/OSUPreferences.h>

#import "OUISoftwareUpdatePrivacyAlert.h"

RCS_ID("$Id$");

@interface OUISoftwareUpdateController (/*Privatee*/) <OSUCheckerTarget>
- (void)_applicationDidFinishLaunchingNotification:(NSNotification *)note;
- (void)_applicationWillTerminateNotification:(NSNotification *)note;
- (void)_applicationDidEnterBackgroundNotification:(NSNotification *)note;
- (void)_applicationWillEnterForegroundNotification:(NSNotification *)note;
@end

@implementation OUISoftwareUpdateController

- init;
{
    if (!(self = [super init]))
        return nil;
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_applicationDidFinishLaunchingNotification:) name:UIApplicationDidFinishLaunchingNotification object:nil];
    [center addObserver:self selector:@selector(_applicationWillTerminateNotification:) name:UIApplicationWillTerminateNotification object:nil];
    [center addObserver:self selector:@selector(_applicationDidEnterBackgroundNotification:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(_applicationWillEnterForegroundNotification:) name:UIApplicationWillEnterForegroundNotification object:nil];
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark -
#pragma mark OSUCheckerTarget

- (OSUPrivacyNoticeResult)checker:(OSUChecker *)checker runPrivacyNoticePanelHavingSeenPreviousVersion:(BOOL)hasSeenPreviousVersion;
{
    if (!_privacyAlert) { // Don't run another one if we still have one up
        _privacyAlert = [[OUISoftwareUpdatePrivacyAlert alloc] initWithDelegate:self];
        [_privacyAlert show];
    }

    // The default value in your Info.plist should be NO. Otherwise a query can go out while the privacy alert it up.
    OBASSERT([[[OSUPreferences automaticSoftwareUpdateCheckEnabled] defaultObjectValue] boolValue] == NO);
    
    // We'll set the preference based on the button tapped.
    return OSUPrivacyNoticeResultShowPreferences;
}

#pragma mark -
#pragma mark OUISoftwareUpdatePrivacyAlertDelegate

- (void)softwareUpdatePrivacyAlert:(OUISoftwareUpdatePrivacyAlert *)alert completedWithAllowingReports:(BOOL)allowReports;
{
    OBPRECONDITION(_privacyAlert == alert);
    
    [_privacyAlert release];
    _privacyAlert = nil;
    
    [[OSUPreferences automaticSoftwareUpdateCheckEnabled] setBoolValue:allowReports];
    
    // If we are now allowed, start a check immediately. On iOS this just means we report our stats once the first time.
    if (allowReports) {
        OSUChecker *checker = [OSUChecker sharedUpdateChecker];
        if (!checker.checkInProgress)
            [checker checkSynchronously];
    }
}

#pragma mark -
#pragma mark Private

static void _startSoftwareUpdate(OUISoftwareUpdateController *self)
{
    [OSUChecker startWithTarget:self];
    [[OSUChecker sharedUpdateChecker] setLicenseType:OSULicenseTypeRetail]; // ... could maybe report something different for sneakypeeks... 'none'?
}

static void _stopSoftwareUpdate(void)
{
    [OSUChecker shutdown];
}

- (void)_applicationDidFinishLaunchingNotification:(NSNotification *)note;
{
    _startSoftwareUpdate(self);
}

// For when running on iOS 3.2.
- (void)_applicationWillTerminateNotification:(NSNotification *)note;
{
    _stopSoftwareUpdate();
}

- (void)_applicationDidEnterBackgroundNotification:(NSNotification *)note;
{
    _stopSoftwareUpdate();
}

- (void)_applicationWillEnterForegroundNotification:(NSNotification *)note;
{
    _startSoftwareUpdate(self);
}

@end

#endif
