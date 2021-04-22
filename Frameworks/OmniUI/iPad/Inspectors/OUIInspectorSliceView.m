// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <OmniUI/OUIInspectorSliceView.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIStackedSlicesInspectorPane.h>

#define DEBUG_SLICE_BORDERS (0)


@implementation OUIInspectorSliceView

+ (void)_drawTopSeparatorInRect:(CGRect)rect alignmentInsets:(UIEdgeInsets)alignmentInsets groupPosition:(OUIInspectorSliceGroupPosition)groupPosition contentScaleFactor:(CGFloat)contentScaleFactor;
{
    if ((groupPosition != OUIInspectorSliceGroupPositionFirst) && (groupPosition != OUIInspectorSliceGroupPositionAlone)) {
        return;
    }
//[[UIColor redColor] set];
    UIBezierPath *path = [UIBezierPath bezierPath];
    path.lineWidth = 1.0f / contentScaleFactor;
    rect.origin.y += 0.5f / contentScaleFactor;
    [path moveToPoint:rect.origin];
    [path addLineToPoint:(CGPoint){ .x = CGRectGetMinX(rect) + CGRectGetWidth(rect), .y = CGRectGetMinY(rect), }];
    [path stroke];
}

+ (void)_drawBottomSeparatorInRect:(CGRect)rect alignmentInsets:(UIEdgeInsets)alignmentInsets groupPosition:(OUIInspectorSliceGroupPosition)groupPosition contentScaleFactor:(CGFloat)contentScaleFactor;
{
//[[UIColor greenColor] set];
    UIBezierPath *path = [UIBezierPath bezierPath];
    if ((groupPosition == OUIInspectorSliceGroupPositionFirst) || (groupPosition == OUIInspectorSliceGroupPositionCenter)) {
        rect.origin.x += alignmentInsets.left;
        rect.size.width -= alignmentInsets.left;
    }
    path.lineWidth = 1.0f / contentScaleFactor;
    rect.origin.y -= 0.5f / contentScaleFactor;
    [path moveToPoint:(CGPoint){ .x = CGRectGetMinX(rect), .y = CGRectGetMaxY(rect), }];
    [path addLineToPoint:(CGPoint){ .x = CGRectGetMinX(rect) + CGRectGetWidth(rect), .y = CGRectGetMaxY(rect), }];
    [path stroke];
}

+ (instancetype)tableSectionSeparatorView;
{
    OUIInspectorSliceView *view = [[[self class] alloc] init];
    view.inspectorSliceGroupPosition = OUIInspectorSliceGroupPositionAlone;
    view.backgroundColor = [OUIInspector backgroundColor];
    return view;
}

- (id)initWithFrame:(CGRect)frame;
{
    self = [super initWithFrame:frame];
    if (self) {
        self.inspectorSliceAlignmentInsets = [OUIInspectorSlice sliceAlignmentInsets];
        self.inspectorSliceGroupPosition = OUIInspectorSliceGroupPositionAlone;
        self.inspectorSliceSeparatorColor = [OUIInspectorSlice sliceSeparatorColor];
        self.backgroundColor = [UIColor whiteColor];
    }
    return self;
}

- (void)drawRect:(CGRect)rect;
{
    // We don't actually need to draw our background - we have a background color that accomplishes that.
    [self drawInspectorSliceBorder];
}

- (CGRect)_contentViewFrameWithInsets:(UIEdgeInsets)contentInsets;
{
    CGRect bounds = self.bounds;
    CGRect contentFrame = UIEdgeInsetsInsetRect(bounds, contentInsets);
    contentFrame.size.height = 29.0f;
    contentFrame.origin.y = floor(CGRectGetMidY(bounds) - (contentFrame.size.height / 2.0f));
    return contentFrame;
}

- (CGRect)_contentViewFrame;
{
    CGRect bounds = self.bounds;
    CGRect contentFrame = UIEdgeInsetsInsetRect(bounds, self.inspectorSliceAlignmentInsets);
    contentFrame.size.height = 29.0f;
    contentFrame.origin.y = floor(CGRectGetMidY(bounds) - (contentFrame.size.height / 2.0f));
    return contentFrame;
}

- (void)setContentView:(UIView *)newView;
{
    if (_contentView == newView) {
        return;
    }
    
    [_contentView removeFromSuperview];
    newView.frame = self._contentViewFrame;
    _contentView = newView;
    [self addSubview:_contentView];
}

#pragma mark - OUIInspectorSliceView Protocol

// These can't be auto-synthesized because they are declared in a protocol
@synthesize inspectorSliceAlignmentInsets;
@synthesize inspectorSliceGroupPosition;
@synthesize inspectorSliceSeparatorColor;

@end


@implementation UIView (OUIInspectorSliceExtensions)

- (UIEdgeInsets)inspectorSliceAlignmentInsets;
{
    return [OUIInspectorSlice sliceAlignmentInsets];
}

- (OUIInspectorSliceGroupPosition)inspectorSliceGroupPosition;
{
    return OUIInspectorSliceGroupPositionAlone;
}

- (UIColor *)inspectorSliceSeparatorColor;
{
    return [OUIInspectorSlice sliceSeparatorColor];
}

- (CGFloat)inspectorSliceTopBorderHeight;
{
    CGFloat borderHeight = 0.0f;
    switch (self.inspectorSliceGroupPosition) {
        case OUIInspectorSliceGroupPositionFirst:
        case OUIInspectorSliceGroupPositionAlone:
            borderHeight = 1.0f;
            break;
        default:
            break;
    }
    return borderHeight;
}

- (CGFloat)inspectorSliceBottomBorderHeight;
{
    CGFloat borderHeight = 0.0f;
    switch (self.inspectorSliceGroupPosition) {
        case OUIInspectorSliceGroupPositionLast:
        case OUIInspectorSliceGroupPositionCenter:
        case OUIInspectorSliceGroupPositionAlone:
            borderHeight = 1.0f;
            break;
        default:
            break;
    }
    return borderHeight;
}

- (void)drawInspectorSliceBackground;
{
    [self.backgroundColor set];
    UIRectFill(self.bounds);
}

- (void)drawInspectorSliceBorder;
{
    CGRect bounds = self.bounds;
    CGFloat contentScaleFactor = self.contentScaleFactor;
    if ((CGRectGetHeight(bounds) <= 0.0f) || (CGRectGetWidth(bounds) <= 0.0f)) {
        return; // Nothing to do here
    }
    
    [self.inspectorSliceSeparatorColor set];
    OUIInspectorSliceGroupPosition groupPosition = self.inspectorSliceGroupPosition;
    if (CGRectGetHeight(bounds) > 1.0f) { // If we are not taller than a point, avoid drawing over ourself. The bottom border is the potentially-interesting one; if we're only one point tall, we're presumably being used as a manual separator.
        [OUIInspectorSliceView _drawTopSeparatorInRect:bounds alignmentInsets:self.inspectorSliceAlignmentInsets groupPosition:groupPosition contentScaleFactor:contentScaleFactor];
    }
    [OUIInspectorSliceView _drawBottomSeparatorInRect:bounds alignmentInsets:self.inspectorSliceAlignmentInsets groupPosition:groupPosition contentScaleFactor:contentScaleFactor];
}

@end
