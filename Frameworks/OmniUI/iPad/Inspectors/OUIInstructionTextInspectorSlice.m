// Copyright 2010-2014 The Omni Group. All rights reserved.
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

- (CGFloat)minimumHeightForWidth:(CGFloat)width;
{
    UILabel *label = (UILabel *)self.view;
    return [label sizeThatFits:CGSizeMake(width, 0)].height;
}

- (UIView *)makeSliceBackgroundView;
{
    return nil;
}

- (CGFloat)paddingToInspectorLeft;
{
    return [super paddingToInspectorLeft] - 6;
}

#pragma mark - UIViewController subclass

- (void)loadView;
{
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, OUIInspectorContentWidth, 0)];
    [label applyStyle:OUILabelStyleInspectorSliceInstructionText];
    
    label.numberOfLines = 0; // No limit
    label.text = _instructionText;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    
    self.view = label;
    
    [self sizeChanged];
}

@end
