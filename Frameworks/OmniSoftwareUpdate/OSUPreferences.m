// Copyright 2001-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUPreferences.h"

#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$");

typedef enum { Daily, Weekly, Monthly } CheckFrequencyMark;

static OFPreference *automaticSoftwareUpdateCheckEnabled = nil;
static OFPreference *checkInterval = nil;
static OFPreference *includeHardwareDetails = nil;
static OFPreference *updatesToIgnore = nil;
static OFPreference *visibleTracks = nil;

@implementation OSUPreferences

+ (void)initialize;
{
    OBINITIALIZE;

#if MAC_APP_STORE
    automaticSoftwareUpdateCheckEnabled = [OFPreference preferenceForKey:@"OSUSendSystemInfoEnabled"];
#else
    automaticSoftwareUpdateCheckEnabled = [OFPreference preferenceForKey:@"AutomaticSoftwareUpdateCheckEnabled"];
#endif
    checkInterval = [OFPreference preferenceForKey:@"OSUCheckInterval"];
    includeHardwareDetails = [OFPreference preferenceForKey:@"OSUIncludeHardwareDetails"];
    updatesToIgnore = [OFPreference preferenceForKey:@"OSUIgnoredUpdates"];
    visibleTracks = [OFPreference preferenceForKey:@"OSUVisibleTracks"];
}

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

@end
