// Copyright 2001-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSToolbar-OAExtensions.h>

#import <Cocoa/Cocoa.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation NSToolbar (OAExtensions)

- (NSUInteger)indexOfFirstItemWithIdentifier:(NSString *)identifier;
{
    NSArray *items = [self items];
    NSUInteger itemCount = [items count];

    for (NSUInteger itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        NSToolbarItem *item = [items objectAtIndex:itemIndex];
        NSString *itemIdentifier = [item itemIdentifier];
        if (OFISEQUAL(itemIdentifier, identifier))
            return itemIndex;
    }

    return NSNotFound;
}

@end
