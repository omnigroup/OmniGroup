// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
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
@property (strong, nonatomic) UIView *bottomSeparator;
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


#pragma mark -
#pragma mark UIViewController subclass

- (void)loadView;
{
    CGRect textWellFrame = CGRectMake(0, 0, 100, kOUIInspectorWellHeight); // Width doesn't matter; we'll get width-resized as we get put in the stack.
    UIView *containerView = [[UIView alloc] initWithFrame:textWellFrame];

    _textWell = [[OUIColorAttributeInspectorWell alloc] initWithFrame:textWellFrame];
    _textWell.style = OUIInspectorTextWellStyleSeparateLabelAndText;
    _textWell.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _textWell.cornerType = OUIInspectorWellCornerTypeLargeRadius;
    _textWell.backgroundType = OUIInspectorWellBackgroundTypeNormal;
    _textWell.label = self.title;
    
    [_textWell addTarget:self action:@selector(showDetails:) forControlEvents:UIControlEventTouchUpInside];

    [containerView addSubview:_textWell];

    _textWell.translatesAutoresizingMaskIntoConstraints = NO;
    containerView.translatesAutoresizingMaskIntoConstraints = NO;

    CGFloat buffer = [OUIInspectorSlice sliceAlignmentInsets].left;

    NSMutableArray *constraintsToActivate = [NSMutableArray array];
    [constraintsToActivate addObject:[containerView.heightAnchor constraintEqualToConstant:kOUIInspectorWellHeight]];
    [constraintsToActivate addObject:[_textWell.leadingAnchor constraintEqualToAnchor:containerView.layoutMarginsGuide.leadingAnchor constant:0]];
    [constraintsToActivate addObject:[_textWell.rightAnchor constraintEqualToAnchor:containerView.rightAnchor constant:buffer * -1]];
    [constraintsToActivate addObject:[_textWell.topAnchor constraintEqualToAnchor:containerView.topAnchor]];
    [constraintsToActivate addObject:[_textWell.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]];
    [NSLayoutConstraint activateConstraints:constraintsToActivate];

    self.view = containerView;
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
