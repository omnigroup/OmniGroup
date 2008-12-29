// Copyright 2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUTAChecker.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniSoftwareUpdate/OSUTestApp/OSUTAChecker.m 79082 2006-09-07 22:52:47Z kc $");


// Preferences keys
static NSString *OSUTargetUserVisibleSystemVersionKey = @"targetUserVisibleSystemVersionString";
static NSString *OSUTargetBundleIdentifierKey = @"targetBundleIdentifier";
static NSString *OSUTargetMarketingVersionKey = @"targetMarketingVersion";
static NSString *OSUTargetBuildVersionKey = @"targetBuildVersion";
static NSString *OSUTargetVisibleTracksStringKey = @"targetVisibleTracksString";


@implementation OSUTAChecker

#pragma mark --
#pragma mark API

+ (NSString *)defaultBundleIdentifier;
{
    return [[NSBundle mainBundle] bundleIdentifier];
}

+ (NSString *)defaultBundleBuildVersionString;
{
    return @"1";
}

+ (NSString *)defaultBundleMarketingVersionString;
{
    return @"1.0";
}

+ (NSString *)defaultUserVisibleSystemVersion;
{
    return [super userVisibleSystemVersion];
}

#pragma mark --
#pragma mark OSUChecker subclass

+ (NSString *)userVisibleSystemVersion;
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:OSUTargetUserVisibleSystemVersionKey];
    return (![NSString isEmptyString:value]) ? value : [self defaultUserVisibleSystemVersion];
}

- (NSString *)targetBundleIdentifier;
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:OSUTargetBundleIdentifierKey];
    return (![NSString isEmptyString:value]) ? value : [[self class] defaultBundleIdentifier];
}

- (NSString *)targetMarketingVersionStringFromBundleInfo:(NSDictionary *)bundleInfo;
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:OSUTargetMarketingVersionKey];
    return (![NSString isEmptyString:value]) ? value : [[self class] defaultBundleMarketingVersionString];
}

- (NSString *)targetBuildVersionStringFromBundleInfo:(NSDictionary *)bundleInfo;
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:OSUTargetBuildVersionKey];
    return (![NSString isEmptyString:value]) ? value : [[self class] defaultBundleBuildVersionString];
}

- (NSArray *)downloadables:(NSArray *)downloadables visibleToTracks:(NSSet *)visibleTracks;
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:OSUTargetVisibleTracksStringKey];
    NSArray *tracks = [value componentsSeparatedByString:@"\n"];
    return [super downloadables:downloadables visibleToTracks:([tracks count] > 0) ? [NSSet setWithArray:tracks] : [NSSet setWithObject:@""]];
}

@end
