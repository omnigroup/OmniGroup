// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInstructionTextInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
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
        UILabel *view = (UILabel *)self.view;
        view.text = _instructionText;
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
    return [UIColor clearColor];
}

#pragma mark - UIViewController subclass

- (void)loadView;
{
    UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [OUIInspector defaultInspectorContentWidth], 0)];
    self.label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, [OUIInspector defaultInspectorContentWidth], 0)];
    [self.label applyStyle:OUILabelStyleInspectorSliceInstructionText];
    
    self.label.numberOfLines = 0; // No limit
    self.label.text = _instructionText;
    self.label.lineBreakMode = NSLineBreakByWordWrapping;

    [containerView addSubview:self.label];

    //constraints
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.label.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
                                              [self.label.leftAnchor constraintEqualToAnchor:containerView.leftAnchor constant:self.class.sliceAlignmentInsets.left],
                                              [self.label.rightAnchor constraintEqualToAnchor:containerView.rightAnchor constant:self.class.sliceAlignmentInsets.right * -1],
                                              [self.label.topAnchor constraintEqualToAnchor:containerView.topAnchor],
                                              [self.label.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]]];

    self.view = containerView;
    
    [self sizeChanged];
}

@end
