// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorAttributeInspectorSlice.h>

#import <OmniUI/OUIColorAttributeInspectorWell.h>
#import <OmniUI/OUIInspectorSelectionValue.h>

#import "OUIParameters.h"

RCS_ID("$Id$")

@interface OUIColorAttributeInspectorSlice ()
@property(nonatomic,retain) OUIColorAttributeInspectorWell *textWell;
@end

@implementation OUIColorAttributeInspectorSlice

@synthesize textWell = _textWell;

- initWithLabel:(NSString *)label;
{
    OBPRECONDITION(![NSString isEmptyString:label]);
    
    if (!(self = [super init]))
        return nil;
    
    self.title = label;
    
    return self;
}

- (void)dealloc;
{
    [_textWell release];
    [super dealloc];
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)loadView;
{
    CGRect textWellFrame = CGRectMake(0, 0, 100, kOUIInspectorWellHeight); // Width doesn't matter; we'll get width-resized as we get put in the stack.
    
    _textWell = [[OUIColorAttributeInspectorWell alloc] initWithFrame:textWellFrame];
    _textWell.style = OUIInspectorTextWellStyleSeparateLabelAndText;
    _textWell.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _textWell.rounded = YES;
    _textWell.label = self.title;
    
    [_textWell addTarget:nil action:@selector(showDetails:) forControlEvents:UIControlEventTouchUpInside];
    
    self.view = _textWell;
}

- (void)viewDidUnload;
{
    self.textWell = nil;
    [super viewDidUnload];
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    
    OUIInspectorSelectionValue *selectionValue = self.selectionValue;
    
    OUIColorAttributeInspectorWell *textWell = (OUIColorAttributeInspectorWell *)self.textWell;
    textWell.color = selectionValue.firstValue;
}

@end
