// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSMenu-OAExtensions.h>

#import <AppKit/NSScreen.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <OmniBase/rcsid.h>
#import <OmniFoundation/NSString-OFExtensions.h>

RCS_ID("$Id$")

static NSString *OAContextMenuLayoutDefaultKey = @"OAContextMenuLayout";

#define MIN_SCREEN_WIDTH (1024)


@implementation NSMenu (OAExtensions)

+ (OAContextMenuLayout) contextMenuLayoutDefaultValue;
{
    OAContextMenuLayout layout;
    
    layout = [[NSUserDefaults standardUserDefaults] integerForKey: OAContextMenuLayoutDefaultKey];
    if (layout > OAContextMenuLayoutCount)
        layout = OAAutodetectContextMenuLayout;
        
    return layout;
}

+ (void) setContextMenuLayoutDefaultValue: (OAContextMenuLayout) newValue;
{
    if (newValue > OAContextMenuLayoutCount)
        newValue = OAAutodetectContextMenuLayout;
    [[NSUserDefaults standardUserDefaults] setInteger: newValue forKey: OAContextMenuLayoutDefaultKey];
}

+ (OAContextMenuLayout) contextMenuLayoutForScreen: (NSScreen *) screen;
{
    OAContextMenuLayout layout;
    
    layout = [self contextMenuLayoutDefaultValue];
    if (layout == OAAutodetectContextMenuLayout) {
        NSRect frame;
        NSArray *screens;
        unsigned int screenIndex, screenCount;;
        
        if (screen)
            screens = [NSArray arrayWithObject: screen];
        else
            screens = [NSScreen screens];

        screenCount = [screens count];
        for (screenIndex = 0; screenIndex < screenCount; screenIndex++) {
            screen = [screens objectAtIndex: screenIndex];
            frame = [screen visibleFrame];

            if (NSWidth(frame) <= MIN_SCREEN_WIDTH)
                return OASmallContextMenuLayout;
        }
        
        return OAWideContextMenuLayout;
    }
    
    return layout;
}

+ (NSString *) lengthAdjustedContextMenuLabel: (NSString *) label layout: (OAContextMenuLayout) layout;
{    
    if (layout == OAWideContextMenuLayout && [label length] > 60)
        return [[label substringToIndex: 60] stringByAppendingString: [NSString horizontalEllipsisString]];
    else if (layout == OASmallContextMenuLayout && [label length] > 30)
        return [[label substringToIndex: 30] stringByAppendingString: [NSString horizontalEllipsisString]];
    return label;
}

- (void) removeAllItems;
{
    while ([self numberOfItems])
        [self removeItemAtIndex: 0];
}

- (NSMenuItem *)itemWithAction:(SEL)action;
{
    unsigned int itemIndex = [self numberOfItems];
    while (itemIndex--) {
        NSMenuItem *item = [self itemAtIndex:itemIndex];
        if ([item action] == action)
            return item;
    }
    return nil;
}

@end
