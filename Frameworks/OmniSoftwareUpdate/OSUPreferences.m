// Copyright 2001-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUPreferences.h>

#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$");

typedef enum { Daily, Weekly, Monthly } CheckFrequencyMark;

static OFPreference *automaticSoftwareUpdateCheckEnabled = nil;
static OFPreference *checkInterval = nil;
static OFPreference *includeHardwareDetails = nil;
static OFPreference *updatesToIgnore = nil;
static OFPreference *visibleTracks = nil;
static OFPreference *unreadNews;
static OFPreference *currentNewsURL;
static OFPreference *newsPublishDate;

@implementation OSUPreferences

+ (void)initialize;
{
    OBINITIALIZE;

    automaticSoftwareUpdateCheckEnabled = [OFPreference preferenceForKey:@"OSUCheckEnabled"];
    checkInterval = [OFPreference preferenceForKey:@"OSUCheckInterval"];
    includeHardwareDetails = [OFPreference preferenceForKey:@"OSUIncludeHardwareDetails"];
    updatesToIgnore = [OFPreference preferenceForKey:@"OSUIgnoredUpdates"];
    visibleTracks = [OFPreference preferenceForKey:@"OSUVisibleTracks"];
    unreadNews = [OFPreference preferenceForKey:@"OSUUnreadNews"];
    currentNewsURL = [OFPreference preferenceForKey:@"OSUCurrentNewsURL"];
    newsPublishDate = [OFPreference preferenceForKey:@"OSUNewsPublishDate"];
}

// This provides the capability to do a one-time migration of a persistent value from AutomaticSoftwareUpdateCheckEnabled to OSUSendSystemInfoEnabled for relevant platforms.
// r240736 changed the automaticSoftwareUpdateCheckEnabled key from AutomaticSoftwareUpdateCheckEnabled to OSUSendSystemInfoEnabled for <bug:///119795> (Bug: Send Anonymous Data needs to be off by default) when building for iOS.
//
// In the case of OmniFocus-iOS, we prompt in first run for permission to collect system info. In versions <= 2.8, the persistent values was stored in AutomaticSoftwareUpdateCheckEnabled.
// Upon upgrading to 2.8, the user's preference was lost and we'd like to retrieve the prior setting as appropriate using this helper.
#if MAC_APP_STORE || TARGET_OS_IPHONE
+ (void)performOneTimeSendSystemInfoPreferenceMigrationIfNecessary;
{
    OFPreference *oldSendSystemInfoEnabledPreference = [OFPreference preferenceForKey:@"AutomaticSoftwareUpdateCheckEnabled"];
    if (![oldSendSystemInfoEnabledPreference hasPersistentValue]) {
        return;
    }

    OBASSERT(automaticSoftwareUpdateCheckEnabled);
    if (![automaticSoftwareUpdateCheckEnabled hasPersistentValue]) {
        [automaticSoftwareUpdateCheckEnabled setBoolValue:[oldSendSystemInfoEnabledPreference boolValue]];
    }
    
    [oldSendSystemInfoEnabledPreference restoreDefaultValue];
}
#endif

+ (OFPreference *)automaticSoftwareUpdateCheckEnabled;
{
    return automaticSoftwareUpdateCheckEnabled;
}

+ (OFPreference *)checkInterval;
{
    return checkInterval;
}

+ (OFPreference *)includeHardwareDetails;
{
    return includeHardwareDetails;
}

+ (OFPreference *)ignoredUpdates;
{
    return updatesToIgnore;
}

+ (NSArray *)visibleTracks;
{
    return [visibleTracks stringArrayValue];
}

+ (void)setVisibleTracks:(NSArray *)orderedTrackList;
{
    OBASSERT(orderedTrackList != nil);
        
    if ([orderedTrackList isEqual:[visibleTracks stringArrayValue]])
        return;
    
#ifdef DEBUG
    NSLog(@"OSU tracks %@ -> %@", [[visibleTracks stringArrayValue] description], [orderedTrackList description]);
#endif
    
    if (![orderedTrackList count] && [orderedTrackList isEqual:[visibleTracks defaultObjectValue]])
        [visibleTracks restoreDefaultValue];
    else 
        [visibleTracks setArrayValue:orderedTrackList];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OSUTrackVisibilityChangedNotification object:self];
}

+ (OFPreference *)unreadNews;
{
    return unreadNews;
}

+ (OFPreference *)currentNewsURL;
{
    return currentNewsURL;
}

+ (OFPreference *)newsPublishDate;
{
    return newsPublishDate;
}
@end
