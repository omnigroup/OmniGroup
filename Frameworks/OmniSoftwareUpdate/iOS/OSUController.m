// Copyright 2010, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUController.h>

#import <OmniFoundation/OFPreference.h>
#import <OmniSoftwareUpdate/OSUChecker.h>
#import <OmniSoftwareUpdate/OSUPreferences.h>
#import <OmniSoftwareUpdate/OSUPrivacyAlert.h>
#import <OmniSoftwareUpdate/OSUCheckerTarget.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

@interface OSUController () <OSUCheckerTarget, OSUPrivacyAlertDelegate>
@end

@implementation OSUController
{
    BOOL _started;
    OSUPrivacyAlert *_privacyAlert;
}

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
}

#pragma mark - OSUCheckerTarget

- (OSUPrivacyNoticeResult)checker:(OSUChecker *)checker runPrivacyNoticePanelHavingSeenPreviousVersion:(BOOL)hasSeenPreviousVersion;
{
#if 1
    // Turning off the alert for now since it is more the norm to automatically do such checks. We still don't do the checks right away (giving the user time to explore our settings and turn it off). Might change this, so keeping the code below around for now...
    OBASSERT([[[OSUPreferences automaticSoftwareUpdateCheckEnabled] defaultObjectValue] boolValue] == YES);
    return OSUPrivacyNoticeResultOK;
#else
    if (!_privacyAlert) { // Don't run another one if we still have one up
        _privacyAlert = [[OSUPrivacyAlert alloc] initWithDelegate:self];
        [_privacyAlert show];
    }

    // The default value in your Info.plist should be NO. Otherwise a query can go out while the privacy alert is up.
    OBASSERT([[[OSUPreferences automaticSoftwareUpdateCheckEnabled] defaultObjectValue] boolValue] == NO);
    
    // We'll set the preference based on the button tapped.
    return OSUPrivacyNoticeResultShowPreferences;
#endif
}

#pragma mark - OSUPrivacyAlertDelegate

- (void)softwareUpdatePrivacyAlert:(OSUPrivacyAlert *)alert completedWithAllowingReports:(BOOL)allowReports;
{
    OBPRECONDITION(_privacyAlert == alert);
    
    _privacyAlert = nil;
    
    [[OSUPreferences automaticSoftwareUpdateCheckEnabled] setBoolValue:allowReports];
    
    // If we are now allowed, start a check immediately. On iOS this just means we report our stats once the first time.
    if (allowReports) {
        OSUChecker *checker = [OSUChecker sharedUpdateChecker];
        if (!checker.checkInProgress)
            [checker checkSynchronously];
    }
}

#pragma mark - Private

static void _startSoftwareUpdate(OSUController *self)
{
    if (self->_started == NO) {
        self->_started = YES;
        [OSUChecker startWithTarget:self];
        [[OSUChecker sharedUpdateChecker] setLicenseType:OSULicenseTypeRetail]; // ... could maybe report something different for sneakypeeks... 'none'?
    }
}

static void _stopSoftwareUpdate(OSUController *self)
{
    if (self->_started == YES) {
        self->_started = NO;
        [OSUChecker shutdown];
    }
}

- (void)_applicationDidFinishLaunchingNotification:(NSNotification *)note;
{
    _startSoftwareUpdate(self);
}

// For when we don't have background support enabled
- (void)_applicationWillTerminateNotification:(NSNotification *)note;
{
    _stopSoftwareUpdate(self);
}

- (void)_applicationDidEnterBackgroundNotification:(NSNotification *)note;
{
    _stopSoftwareUpdate(self);
}

- (void)_applicationWillEnterForegroundNotification:(NSNotification *)note;
{
    _startSoftwareUpdate(self);
}

@end
