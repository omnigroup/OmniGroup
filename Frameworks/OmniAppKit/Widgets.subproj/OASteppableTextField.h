// Copyright 2006-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OASteppableTextField.h 89471 2007-08-01 23:55:27Z kc $

#import <AppKit/NSTextField.h>

@interface OASteppableTextField : NSTextField 
{
    int stepperTracking;
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
