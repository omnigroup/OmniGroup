// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSControl.h>

@class NSValueTransformer;
@class NSTextField;

#import <AppKit/NSNibDeclarations.h> // For IBAction, IBOutlet

@interface OAVectorView : NSControl
{
    IBOutlet NSTextField *xField;
    IBOutlet NSTextField *yField;
    IBOutlet NSTextField *commaTextField;
    
    id observedObjectForVector;
    NSString *observedKeyPathForVector;
    NSValueTransformer *vectorValueTransformer;
}

// Actions
- (IBAction)vectorTextFieldAction:(id)sender;

// API
- (void)setIsMultiple:(BOOL)flag;
- (BOOL)isMultiple;

- (NSTextField *)xField;
- (NSTextField *)yField;

@end
