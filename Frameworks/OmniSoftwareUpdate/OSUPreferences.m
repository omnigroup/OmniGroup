// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUPreferences.h>

@import OmniFoundation;

#if OSU_FULL
#import "OSUItem.h"
#endif

RCS_ID("$Id$");

typedef enum { Daily, Weekly, Monthly } CheckFrequencyMark;

static OFPreference *automaticSoftwareUpdateCheckEnabled;
static OFPreference *checkInterval;
static OFPreference *includeHardwareDetails;
static OFPreference *updatesToIgnore;
static OFPreference *visibleTracksPreference;
static OFPreference *memorableTracksPreference;
static OFPreference *unreadNews;
static OFPreference *currentNewsURL;
static OFPreference *newsPublishDate;
static NSArray <NSString *> *_visibleTracks;

@implementation OSUPreferences

+ (void)initialize;
{
    OBINITIALIZE;

    automaticSoftwareUpdateCheckEnabled = [OFPreference preferenceForKey:@"OSUCheckEnabled"];
    checkInterval = [OFPreference preferenceForKey:@"OSUCheckInterval"];
    includeHardwareDetails = [OFPreference preferenceForKey:@"OSUIncludeHardwareDetails"];
    updatesToIgnore = [OFPreference preferenceForKey:@"OSUIgnoredUpdates"];
    visibleTracksPreference = [OFPreference preferenceForKey:@"OSUVisibleTracks"];
    memorableTracksPreference = [OFPreference preferenceForKey:@"OSUMemorableTracks"];
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

static NSArray <NSString *> *_memorableTracksFromTracks(NSArray <NSString *> *orderedTracks);
static NSArray <NSString *> *_memorableTracksFromTracks(NSArray <NSString *> *orderedTracks)
{
#if OSU_FULL
    NSSet <NSString *> *allMemorableTracks = [NSSet setWithArray:[memorableTracksPreference stringArrayValue]];
    NSArray <NSString *> *elaboratedTracks = [OSUItem elaboratedTracks:orderedTracks];
    NSArray <NSString *> *filteredTracks = [elaboratedTracks select:^BOOL(NSString *track) {
        return [allMemorableTracks containsObject:track];
    }];
    return [OSUItem dominantTracks:filteredTracks];
#else
    // App Store builds don't actually pay attention to the software update feed, so this can be a no-op
    return orderedTracks;
#endif
}

+ (NSArray <NSString *> *)visibleTracks;
{
    if (_visibleTracks != nil)
        return _visibleTracks;

    NSArray <NSString *> *savedTracks = [visibleTracksPreference stringArrayValue];
    _visibleTracks = _memorableTracksFromTracks(savedTracks);
    return _visibleTracks;
}

+ (void)setVisibleTracks:(NSArray <NSString *> *)orderedTrackList;
{
    OBASSERT(orderedTrackList != nil);
        
    if ([orderedTrackList isEqual:[self visibleTracks]])
        return;
    
#ifdef DEBUG
    NSLog(@"OSU tracks %@ -> %@", [[visibleTracksPreference stringArrayValue] description], [orderedTrackList description]);
#endif

    _visibleTracks = orderedTrackList;
    NSArray <NSString *> *saveTracks = _memorableTracksFromTracks(orderedTrackList);

    if ([saveTracks isEqual:[visibleTracksPreference defaultObjectValue]])
        [visibleTracksPreference restoreDefaultValue];
    else 
        [visibleTracksPreference setArrayValue:saveTracks];
    
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
