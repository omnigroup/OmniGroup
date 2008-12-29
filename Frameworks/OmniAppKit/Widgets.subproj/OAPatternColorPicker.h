// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

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
