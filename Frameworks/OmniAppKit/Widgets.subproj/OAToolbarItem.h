// Copyright 2001-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAToolbarItem.h 93428 2007-10-25 16:36:11Z kc $

#import <AppKit/NSToolbarItem.h>

#define OAToolbarItemTintOverridePreference (@"ToolbarItemTint")

@interface OAToolbarItem : NSToolbarItem
{
    NSImage *_optionKeyImage;
    NSString *_optionKeyLabel;
    NSString *_optionKeyToolTip;
    SEL _optionKeyAction;
    
    id _delegate;
    BOOL inOptionKeyState;
    BOOL observingTintChanges;
    BOOL observingTintOverrideChanges;
    
    // If these are non-nil, we'll change our image when the control tint changes.
    NSString *tintedImageStem, *tintedOptionImageStem;
    NSBundle *tintedImageBundle;
}

- (id)delegate;
- (void)setDelegate:(id)delegate;
    // Right now, the only thing we're doing with our delegate is using it as a validator; AppKit's auto-validation scheme can be useful for changing more attributes than just enabled/disabled, but it currently only works for items that have a target and action, which many custom toolbar items don't.

- (NSImage *)optionKeyImage;
- (void)setOptionKeyImage:(NSImage *)image;
- (NSString *)optionKeyLabel;
- (void)setOptionKeyLabel:(NSString *)label;
- (NSString *)optionKeyToolTip;
- (void)setOptionKeyToolTip:(NSString *)toolTip;
    // Show an alternate image, label, and tooltop if the user holds the option/alternate key.

- (SEL)optionKeyAction;
- (void)setOptionKeyAction:(SEL)action;
    // And perform an alternate action when clicked in the option-key-down state

- (void)setUsesTintedImage:(NSString *)imageName inBundle:(NSBundle *)imageBundle;
- (void)setUsesTintedImage:(NSString *)imageName optionKeyImage:(NSString *)alternateImageName inBundle:(NSBundle *)imageBundle;

@end
