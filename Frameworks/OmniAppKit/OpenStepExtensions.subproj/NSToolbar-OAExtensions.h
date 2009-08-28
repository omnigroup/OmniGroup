// Copyright 2001-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSToolbar.h>

@class NSView;

@interface NSToolbar (OAExtensions)

#if !defined(MAC_OS_X_VERSION_10_6) || (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6)
- (NSWindow *)window;
- (NSView *)toolbarView;

// Accessors for new NSToolbar options available in Mac OS X 10.1. 

- (BOOL)alwaysCustomizableByDrag;
- (void)setAlwaysCustomizableByDrag:(BOOL)flag;
    // When YES, items can be dragged around or off the toolbar even when it's not in customize mode. They're still clickable, of course.

- (BOOL)showsContextMenu;
- (void)setShowsContextMenu:(BOOL)flag;
    // When NO, the standard toolbar customization context-menu won't show up when the bar is right-clicked. 
    
- (unsigned int)indexOfFirstMovableItem;
- (void)setIndexOfFirstMovableItem:(unsigned int)anIndex;
    // Items before this index can't be reordered or removed even if the toolbar is customizable.
#endif

- (NSUInteger)indexOfFirstItemWithIdentifier:(NSString *)identifier;

@end
