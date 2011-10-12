// Copyright 2006, 2010-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUTAChecker.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");


// Preferences keys
static NSString * const OSUTargetBundleIdentifierKey = @"targetBundleIdentifier";
static NSString * const OSUTargetMarketingVersionKey = @"targetMarketingVersion";
static NSString * const OSUTargetBuildVersionKey = @"targetBuildVersion";
static NSString * const OSUTargetTrackStringKey = @"targetReleaseTrack";


@implementation OSUTAChecker

#pragma mark --
#pragma mark OSUChecker subclass

- (NSString *)applicationIdentifier;
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:OSUTargetBundleIdentifierKey];
    return (![NSString isEmptyString:value]) ? value : [super applicationIdentifier];
}

- (OFVersionNumber *)applicationMarketingVersion
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:OSUTargetMarketingVersionKey];
    if (![NSString isEmptyString:value]) {
        return [[[OFVersionNumber alloc] initWithVersionString:value] autorelease];
    } else {
        return [super applicationMarketingVersion];
    }
}

- (NSString *)applicationEngineeringVersion;
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:OSUTargetBuildVersionKey];
    return (![NSString isEmptyString:value]) ? value : [super applicationEngineeringVersion];
}

- (NSString *)applicationTrack;
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:OSUTargetTrackStringKey];
    return (![NSString isEmptyString:value]) ? value : [super applicationTrack];
}

#if 0
- (NSArray *)downloadables:(NSArray *)downloadables visibleToTracks:(NSSet *)visibleTracks;
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:OSUTargetVisibleTracksStringKey];
    NSArray *tracks = [value componentsSeparatedByString:@"\n"];
    return [super downloadables:downloadables visibleToTracks:([tracks count] > 0) ? [NSSet setWithArray:tracks] : [NSSet setWithObject:@""]];
}
#endif

- (IBAction)fakeTimedCheck:sender;
{
    NSDate *verySoon = [NSDate dateWithTimeIntervalSinceNow:0.25];
    [[NSUserDefaults standardUserDefaults] setObject:verySoon forKey:@"OSUNextScheduledCheck"];
    objc_msgSend(self, @selector(_initiateCheck));
}

@end
