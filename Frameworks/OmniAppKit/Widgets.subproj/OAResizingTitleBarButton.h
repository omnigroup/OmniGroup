// Copyright 2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSButton.h>

/*
 This is a button that inserts itself in the title bar of a given window. The button registers for appropriate notifications to detect when the space available in the title bar has changed. When the space changes, the button calls back to a user-provided block that should provide a new title string that will allow the button to fit in the available space (or nil to hide the button).
 */

@class OAResizingTitleBarButton; // forward declaration for the callback typedef

typedef NSString *(^OATitleBarButtonTextForButtonCallback)(OAResizingTitleBarButton *button, CGFloat widthAvailable, NSColor **textColorOut);

@interface OAResizingTitleBarButton : NSButton

// The window will retain the returned instance using an associated object. The returned instance will retain the callback. To avoid retain cycles, the callback must not retain the window. If called again with the same key-window pair, the existing button will be assigned a new callback block and will be updated in place.
+ (instancetype)titleBarButtonWithKey:(const void *)key forWindow:(NSWindow *)window textCallback:(OATitleBarButtonTextForButtonCallback)callback;
+ (void)hideTitleBarButtonWithKey:(const void *)key forWindow:(NSWindow *)window;

// utility method for use by callback blocks to determine the width of a putative button title
- (CGFloat)widthForText:(NSString *)text;
@end
