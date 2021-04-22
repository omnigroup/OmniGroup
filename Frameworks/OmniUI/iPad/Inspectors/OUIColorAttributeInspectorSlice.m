// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorAttributeInspectorSlice.h>

#import <OmniUI/OUIColorAttributeInspectorWell.h>
#import <OmniUI/OUIInspectorSelectionValue.h>
#import <OmniUI/OUIInspector.h>

#import "OUIParameters.h"

NS_ASSUME_NONNULL_BEGIN

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

- (nullable NSString *)nibName
{
    return nil;
}

- (nullable NSBundle *)nibBundle
{
    return nil;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;

    _textWell = [[OUIColorAttributeInspectorWell alloc] init];
    _textWell.translatesAutoresizingMaskIntoConstraints = NO;
    _textWell.style = OUIInspectorTextWellStyleSeparateLabelAndText;
    _textWell.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _textWell.cornerType = OUIInspectorWellCornerTypeLargeRadius;
    _textWell.backgroundType = OUIInspectorWellBackgroundTypeNormal;
    _textWell.label = self.title;
    _textWell.labelColor = [OUIInspector labelTextColor];

    [_textWell addTarget:self action:@selector(showDetails:) forControlEvents:UIControlEventTouchUpInside];

    [self.contentView addSubview:_textWell];
    
    UIView *view = self.view;
    [view addSubview:self.contentView];
    
    [self.contentView.topAnchor constraintEqualToAnchor:view.topAnchor].active = YES;
    [self.contentView.rightAnchor constraintEqualToAnchor:view.rightAnchor].active = YES;
    [self.contentView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor].active = YES;
    [self.contentView.leftAnchor constraintEqualToAnchor:view.leftAnchor].active = YES;

    NSMutableArray *constraintsToActivate = [NSMutableArray array];
    [constraintsToActivate addObject:[self.contentView.heightAnchor constraintEqualToConstant:kOUIInspectorWellHeight]];
    [constraintsToActivate addObject:[_textWell.leftAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leftAnchor]];
    
    NSLayoutConstraint *rightMarginLayoutConstraint = [_textWell.rightAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.rightAnchor];
    [constraintsToActivate addObject:rightMarginLayoutConstraint];
    self.rightMarginLayoutConstraint = rightMarginLayoutConstraint;
    
    [constraintsToActivate addObject:[_textWell.topAnchor constraintEqualToAnchor:self.contentView.topAnchor]];
    [constraintsToActivate addObject:[_textWell.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor]];
    [NSLayoutConstraint activateConstraints:constraintsToActivate];
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

NS_ASSUME_NONNULL_END
