// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUController.h>

#import <OmniFoundation/OFPreference.h>
#import <OmniSoftwareUpdate/OSUChecker.h>
#import <OmniSoftwareUpdate/OSUPreferences.h>
#import <OmniSoftwareUpdate/OSUCheckerTarget.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

@interface OSUController () <OSUCheckerTarget>
@end

@implementation OSUController
{
    BOOL _started;
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
    // Alert code was pruned in r226988 because the alert code was never finished. OmniFocus will include the question in its first launch experience. Other apps are just using a switch in Settings for now. We default to not sharing information at Apple's request.
    OBASSERT([[[OSUPreferences automaticSoftwareUpdateCheckEnabled] defaultObjectValue] boolValue] == YES);
    return OSUPrivacyNoticeResultOK;
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
