// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAPatternColorPicker.h 68913 2005-10-03 19:36:19Z kc $

#import <AppKit/NSColorPicker.h>

@class NSImageView;

#import <AppKit/NSNibDeclarations.h> // For IBAction, IBOutlet

@interface OAPatternColorPicker : NSColorPicker <NSColorPickingCustom>
{
    IBOutlet NSView      *view;
    IBOutlet NSImageView *imageView;
}

- (IBAction)imageChanged:(id)sender;

@end
