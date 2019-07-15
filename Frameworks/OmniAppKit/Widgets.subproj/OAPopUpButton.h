// Copyright 1998-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSNibDeclarations.h> // For IBOutlet

@class NSTextField;

// This class adds a label outlet, intended to be hooked up to a TextField which contains an explanatory label for the control. As per Aqua HIG, OAPopUpButton will change the text color of its associated label field to reflect its own enabled/disabled state.

@interface OAPopUpButton : NSPopUpButton
{
    IBOutlet NSTextField *label;
}

@end
