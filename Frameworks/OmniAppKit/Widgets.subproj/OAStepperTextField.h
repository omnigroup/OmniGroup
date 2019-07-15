// Copyright 2004-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSTextField.h>

#import <OmniAppKit/OASteppableTextField.h>

@class NSString;	// Foundation
@class NSStepper;	//  AppKit


@interface OAStepperTextField : OASteppableTextField
{
    IBOutlet NSControl *labelControl;
    IBOutlet NSStepper *stepper;
}

// API

- (NSString *)label;
- (void)setLabel:(NSString *)newValue;

- (id)labelControl;
- (void)setLabelControl:(id)newValue;

- (id)stepper;
- (void)setStepper:(id)newValue;

@end
