// Copyright 2006-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSTextField.h>

@interface OASteppableTextField : NSTextField 
{
    double stepperTracking;
}

- (void)stepperAction:(id)sender;

- (BOOL)validateSteppedObjectValue:(id)objectValue;

@end

@interface NSFormatter (OASteppableTextFieldFormatter)
- (id)stepUpValue:(id)anObjectValue;
- (id)largeStepUpValue:(id)anObjectValue;
- (id)stepDownValue:(id)anObjectValue;
- (id)largeStepDownValue:(id)anObjectValue;
@end
