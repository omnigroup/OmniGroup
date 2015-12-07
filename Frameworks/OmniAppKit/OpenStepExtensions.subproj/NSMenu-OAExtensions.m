// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
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

+ (OAContextMenuLayout)contextMenuLayoutDefaultValue;
{
    OAContextMenuLayout layout = (OAContextMenuLayout)[[NSUserDefaults standardUserDefaults] integerForKey: OAContextMenuLayoutDefaultKey];
    if (layout > OAContextMenuLayoutCount)
        layout = OAAutodetectContextMenuLayout;
        
    return layout;
}

+ (void)setContextMenuLayoutDefaultValue:(OAContextMenuLayout)newValue;
{
    if (newValue > OAContextMenuLayoutCount)
        newValue = OAAutodetectContextMenuLayout;
    [[NSUserDefaults standardUserDefaults] setInteger:newValue forKey:OAContextMenuLayoutDefaultKey];
}

+ (OAContextMenuLayout) contextMenuLayoutForScreen: (NSScreen *) originalScreen;
{
    OAContextMenuLayout layout = [self contextMenuLayoutDefaultValue];
    
    if (layout == OAAutodetectContextMenuLayout) {
        NSArray *screens;        
        if (originalScreen)
            screens = [NSArray arrayWithObject: originalScreen];
        else
            screens = [NSScreen screens];

        for (NSScreen *screen in screens) {
            NSRect frame = [screen visibleFrame];
            if (NSWidth(frame) <= MIN_SCREEN_WIDTH)
                return OASmallContextMenuLayout;
        }
        
        return OAWideContextMenuLayout;
    }
    
    return layout;
}

+ (NSString *)lengthAdjustedContextMenuLabel:(NSString *)label layout:(OAContextMenuLayout)layout;
{    
    if (layout == OAWideContextMenuLayout && [label length] > 60)
        return [[label substringToIndex: 60] stringByAppendingString: [NSString horizontalEllipsisString]];
    else if (layout == OASmallContextMenuLayout && [label length] > 30)
        return [[label substringToIndex: 30] stringByAppendingString: [NSString horizontalEllipsisString]];
    return label;
}

- (NSMenuItem *)itemWithAction:(SEL)action;
{
    for (NSMenuItem *item in [self itemArray])
        if ([item action] == action)
            return item;
    return nil;
}

- (void)addSeparatorIfNeeded;
{
    if ([self numberOfItems] && ![[self itemAtIndex:[self numberOfItems] - 1] isSeparatorItem])
        [self addItem:[NSMenuItem separatorItem]];
}

@end
