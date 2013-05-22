// Copyright 2001-2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUPreferences.h"

#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/NSUserDefaults-OFExtensions.h>
#import <OmniBase/OmniBase.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE // Not including OSUItem on iOS currently
#import "OSUItem.h"
#endif

RCS_ID("$Id$");

typedef enum { Daily, Weekly, Monthly } CheckFrequencyMark;

static OFPreference *automaticSoftwareUpdateCheckEnabled = nil;
static OFPreference *checkInterval = nil;
static OFPreference *includeHardwareDetails = nil;
static OFPreference *includeOpenGLDetails = nil;
static OFPreference *updatesToIgnore = nil;
static OFPreference *visibleTracks = nil;

@implementation OSUPreferences

+ (void)initialize;
{
    OBINITIALIZE;
    automaticSoftwareUpdateCheckEnabled = [[OFPreference preferenceForKey:@"AutomaticSoftwareUpdateCheckEnabled"] retain];
    checkInterval = [[OFPreference preferenceForKey:@"OSUCheckInterval"] retain];
    includeHardwareDetails = [[OFPreference preferenceForKey:@"OSUIncludeHardwareDetails"] retain];
    includeOpenGLDetails = [[OFPreference preferenceForKey:@"OSUIncludeOpenGLDetails"] retain];
    updatesToIgnore = [[OFPreference preferenceForKey:@"OSUIgnoredUpdates"] retain];
    visibleTracks = [[OFPreference preferenceForKey:@"OSUVisibleTracks"] retain];
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

+ (OFPreference *)includeOpenGLDetails;
{
    return includeOpenGLDetails;
}

+ (OFPreference *)ignoredUpdates;
{
    return updatesToIgnore;
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE // Not including OSUItem on iOS currently
+ (void)setItem:(OSUItem *)anItem isIgnored:(BOOL)shouldBeIgnored;
{
    NSString *itemRepr = [[anItem buildVersion] cleanVersionString];
    if (!itemRepr)
        return;
    itemRepr = [@"v" stringByAppendingString:itemRepr];
    
    OFPreference *currentlyIgnored = [self ignoredUpdates];
    NSMutableArray *ignorance = [[currentlyIgnored stringArrayValue] mutableCopy];
    
    if (shouldBeIgnored && ![ignorance containsObject:itemRepr]) {
        [ignorance addObject:itemRepr];
        [ignorance sortUsingSelector:@selector(compare:)];
        [currentlyIgnored setArrayValue:ignorance];
    } else if (!shouldBeIgnored && [ignorance containsObject:itemRepr]) {
        [ignorance removeObject:itemRepr];
        [currentlyIgnored setArrayValue:ignorance];
        if (![currentlyIgnored hasNonDefaultValue])
            [currentlyIgnored restoreDefaultValue];
    }
    
    [ignorance release];
}


+ (BOOL)itemIsIgnored:(OSUItem *)anItem;
{
    OFVersionNumber *itemRepr = [anItem buildVersion];
    if (itemRepr) {
        if([[[self ignoredUpdates] stringArrayValue] containsObject:[@"v" stringByAppendingString:[itemRepr cleanVersionString]]])
            return YES;
    }
    
    NSString *itemTrack = [anItem track];
    if (![OSUItem isTrack:itemTrack includedIn:[self visibleTracks]])
        return YES;
    
    return NO;
}
#endif

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
