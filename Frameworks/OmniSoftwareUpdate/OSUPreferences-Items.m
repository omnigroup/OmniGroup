// Copyright 2001-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUPreferences-Items.h"

#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/OFPreference.h>

#import "OSUItem.h"

@implementation OSUPreferences (Items)

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

@end
