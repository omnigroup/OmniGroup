// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIEmptyPaddingInspectorSlice.h>

RCS_ID("$Id$")

#define DEBUG_EMPTYPADDING (0)

// Custom view necessary to avoid assertions about not knowing what sort of auto-padding to do.
@interface OUIEmptyPaddingInspectorSliceView : UIView
@end

@implementation OUIEmptyPaddingInspectorSliceView

#if DEBUG_EMPTYPADDING
- (void)drawRect:(CGRect)rect;
{
    [[UIColor yellowColor] set];
    UIRectFill(rect);
}
#endif // DEBUG_EMPTYPADDING

@end


@interface OUIEmptyPaddingInspectorSlice ()
@property(nonatomic,assign) BOOL isGroupSpacer;
@end


@implementation OUIEmptyPaddingInspectorSlice

+ (instancetype)groupSpacerSlice;
{
    OUIEmptyPaddingInspectorSlice *slice = [[[self class] alloc] init];
    slice.isGroupSpacer = YES;
    slice.view.autoresizingMask = UIViewAutoresizingNone;
    return slice;
}

+ (UIEdgeInsets)sliceAlignmentInsets;
{
    return (UIEdgeInsets) { .left = 0.0f, .right = 0.0f, .top = 0.0f, .bottom = 0.0f };
}

#pragma mark - UIViewController subclass

- (void)loadView;
{
    UIView *view = [[OUIEmptyPaddingInspectorSliceView alloc] initWithFrame:CGRectZero];
    view.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    self.view = view;
}

#pragma mark - OUIInspectorSlice subclass

- (BOOL)includesInspectorSliceGroupSpacerOnTop;
{
    return YES;
}

- (BOOL)includesInspectorSliceGroupSpacerOnBottom;
{
    return YES;
}

- (UIView *)makeSliceBackgroundView;
{
    // We don't want a background view.
    return nil;
}

- (CGFloat)minimumHeightForWidth:(CGFloat)width;
{
    if (self.isGroupSpacer) {
        return [[self class] paddingBetweenSliceGroups]; // An attempt to match the space that UITableView leaves between groups
    }
    return 0;
}

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    // Show up no matter what
    return YES;
}

@end
