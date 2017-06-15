// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInstructionTextInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorAppearance.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspectorWell.h>
#import <OmniUI/OUIDrawing.h>
#import <OmniUI/UILabel-OUITheming.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUIInstructionTextInspectorSlice

+ (UIEdgeInsets)sliceAlignmentInsets;
{
    // Explano-text should be indented relative to the inset of other slices
    UIEdgeInsets sliceAlignmentInsets = [super sliceAlignmentInsets];
    sliceAlignmentInsets.left += 6;
    sliceAlignmentInsets.right += 6;

    return sliceAlignmentInsets;
}

+ (instancetype)sliceWithInstructionText:(NSString *)text; 
{
    return [[self alloc] initWithInstructionText:text];
}

- initWithInstructionText:(NSString *)text;
{
    if (!(self = [super init]))
        return nil;
    
    self.instructionText = text;
    
    return self;
}

@synthesize instructionText = _instructionText;
- (void)setInstructionText:(NSString *)text;
{
    if (OFISEQUAL(_instructionText, text))
        return;
    
    _instructionText = [text copy];
    
    if ([self isViewLoaded]) {
        self.label.text = _instructionText;
        [self sizeChanged];
    }
}

#pragma mark - OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return YES;
}

- (UIColor *)sliceBackgroundColor;
{
    return [OUIInspector backgroundColor];
}

- (BOOL)includesInspectorSliceGroupSpacerOnTop;
{
    CGFloat topInset = [self class].sliceAlignmentInsets.top;
    return (topInset > 0);
}

- (BOOL)includesInspectorSliceGroupSpacerOnBottom;
{
    CGFloat bottomInset = [self class].sliceAlignmentInsets.bottom;
    return (bottomInset > 0);
}

#pragma mark - UIViewController subclass

- (void)loadView;
{
    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.label = [[UILabel alloc] init];
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.label applyStyle:OUILabelStyleInspectorSliceInstructionText];
    
    self.label.numberOfLines = 0; // No limit
    self.label.text = _instructionText;
    self.label.lineBreakMode = NSLineBreakByWordWrapping;

    [self.contentView addSubview:self.label];

    //constraints

    [NSLayoutConstraint activateConstraints:
     @[
       [self.label.leftAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leftAnchor],
       [self.label.rightAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.rightAnchor],
       [self.label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:self.class.sliceAlignmentInsets.top],
       [self.label.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:self.class.sliceAlignmentInsets.bottom]
       ]];

    UIView *view = [[UIView alloc] init];
    [view addSubview:self.contentView];
    
    [self.contentView.topAnchor constraintEqualToAnchor:view.topAnchor].active = YES;
    [self.contentView.rightAnchor constraintEqualToAnchor:view.rightAnchor].active = YES;
    [self.contentView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor].active = YES;
    [self.contentView.leftAnchor constraintEqualToAnchor:view.leftAnchor].active = YES;
    
    self.view = view;
    
    [self sizeChanged];
}

#pragma mark OUIInspectorThemedApperance

- (void)themedAppearanceDidChange:(OUIThemedAppearance *)changedAppearance;
{
    [super themedAppearanceDidChange:changedAppearance];
    
    OUIInspectorAppearance *appearance = OB_CHECKED_CAST_OR_NIL(OUIInspectorAppearance, changedAppearance);
    
    self.contentView.backgroundColor = appearance.InspectorBackgroundColor;
    self.label.textColor = appearance.InspectorTextColor;
    
}

@end
