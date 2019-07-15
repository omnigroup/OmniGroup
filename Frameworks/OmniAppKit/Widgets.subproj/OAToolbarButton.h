// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSButton.h>

@class NSPopUpButton, NSToolbarItem;

#import <AppKit/NSNibDeclarations.h> // For IBOutlet

@interface OAToolbarButton : NSButton
{
    BOOL isShowingMenu;
}

// API
@property (weak) NSToolbarItem *toolbarItem;
@property (weak) IBOutlet id delegate;

- (void)_showMenu;

@end

@interface NSObject (OAToolbarButtonDelegate)
- (NSPopUpButton *)popUpButtonForToolbarButton:(OAToolbarButton *)button;
@end
