// Copyright 2001-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSToolbar-OAExtensions.h"

#import <Cocoa/Cocoa.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation NSToolbar (OAExtensions)

// Get rid of these terrible hacks
#if !defined(MAC_OS_X_VERSION_10_6) || (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6)
// We could optimize this code to cache the resolved ivars and offsets, but first we should check to make sure we still need to be mucking with private instance variables.

- (NSWindow *)window;
{
#if __OBJC2__
    void *w = nil;
    object_getInstanceVariable(self, "_window", &w);
    return w;
#else
    return _window;
#endif
}

- (NSView *)toolbarView;
{
#if __OBJC2__
    void *v = nil;
    object_getInstanceVariable(self, "_toolbarView", &v);
    return v;
#else
    return _toolbarView;
#endif
}

static struct __tbFlags *getPrivateToolbarFlags(NSToolbar *tb)
{
    Ivar flagStructIvar = class_getInstanceVariable([NSToolbar class], "_tbFlags");
    ptrdiff_t flagStructOffset = ivar_getOffset(flagStructIvar);
    return (struct __tbFlags *)( ((void *)tb) + flagStructOffset );
}

- (BOOL)alwaysCustomizableByDrag;
{
    return getPrivateToolbarFlags(self)->clickAndDragPerformsCustomization;
}

- (void)setAlwaysCustomizableByDrag:(BOOL)flag;
{
    getPrivateToolbarFlags(self)->clickAndDragPerformsCustomization = (unsigned int)flag;
}

- (BOOL)showsContextMenu;
{
    return !getPrivateToolbarFlags(self)->showsNoContextMenu;
}

- (void)setShowsContextMenu:(BOOL)flag;
{
    getPrivateToolbarFlags(self)->showsNoContextMenu = (unsigned int)!flag;
}
    
- (unsigned int)indexOfFirstMovableItem;
{
    return getPrivateToolbarFlags(self)->firstMoveableItemIndex;
}

- (void)setIndexOfFirstMovableItem:(unsigned int)anIndex;
{
    if (anIndex <= [[self items] count])
        getPrivateToolbarFlags(self)->firstMoveableItemIndex = anIndex;
}
#endif

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
