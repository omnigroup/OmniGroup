// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorOptionWheel.h>

#import <OmniUI/OUIInspectorOptionWheelItem.h>
#import <OmniUI/OUIInspectorOptionWheelSelectionIndicator.h>
#import <OmniUI/OUIInspectorWell.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFNull.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@interface OUIInspectorOptionWheel (/*Private*/)
- (OUIInspectorOptionWheelItem *)_closestItemToCenter;
- (void)_snapToSelectionAnimated:(BOOL)animated;
- (void)_selectClosestItemAndSendAction;
- (void)_selectOptionWheelItem:(id)sender;
@end

@interface OUIInspectorOptionWheelScrollView : UIScrollView
@end

@implementation OUIInspectorOptionWheelScrollView 

- (BOOL)touchesShouldCancelInContentView:(UIView *)view;
{
    return YES;
}

- (void)layoutSubviews;
{
    OUIInspectorOptionWheel *wheel = (OUIInspectorOptionWheel *)self.delegate;
    OBASSERT([wheel isKindOfClass:[OUIInspectorOptionWheel class]]);
    
    CGRect bounds = self.bounds;
    
    const CGFloat kItemSpacingX = 1;
    const CGFloat kItemSpacingY = 3;
    
    const CGFloat itemSize = CGRectGetHeight(bounds) - 2*kItemSpacingY;
    
    // We want to have the selection indicator in the middle and be able to scroll the items on the extreme edges to be centered under it.
    const CGFloat edgeSpace = CGRectGetWidth(bounds)/2 - itemSize/2;
    
    CGFloat xOffset = 0;
    for (OUIInspectorOptionWheelItem *item in wheel.items) {
        item.frame = CGRectMake(xOffset, kItemSpacingY, itemSize, itemSize);
        if (item.superview != self)
            [self addSubview:item];
        
        xOffset += kItemSpacingX + itemSize;
    }
    
    self.contentSize = CGSizeMake(xOffset, CGRectGetHeight(bounds));
    self.contentInset = UIEdgeInsetsMake(0, edgeSpace, 0, edgeSpace);
}

@end


@implementation OUIInspectorOptionWheel

static CGFunctionRef BackgroundShadingFunction;

static void _backgroundShadingEvaluate(void *info, const CGFloat *in, CGFloat *out)
{
    OBPRECONDITION(info == NULL);
    
    CGFloat t = *in;
    
    t = 2*fabs(t - 0.5); // ramp up/down
    t = pow(t, kOUIInspectorOptionWheelGradientPower); // flatten the curve

    // Interpolate between two grays.
    const CGFloat minGray = kOUIInspectorOptionWheelEdgeGradientGray;
    const CGFloat maxGray = kOUIInspectorOptionWheelMiddleGradientGray;
    out[0] = t*minGray + (1-t)*maxGray;
    out[1] = 1; // alpha;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    CGFloat domain[] = {0, 1}; // 0..1 input
    CGFloat range[] = {0, 1, 0, 1}; // gray/alpha output
    
    CGFunctionCallbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.evaluate = _backgroundShadingEvaluate;
    
    BackgroundShadingFunction = CGFunctionCreate(NULL/*info*/, 1/*domain*/, domain, 2/*range*/, range, &callbacks);
}

static id _commonInit(OUIInspectorOptionWheel *self)
{
    self.opaque = NO;
    self.backgroundColor = nil;
    self.clearsContextBeforeDrawing = YES;
    
    self->_scrollView = [[OUIInspectorOptionWheelScrollView alloc] init];
    self->_scrollView.opaque = NO;
    self->_scrollView.backgroundColor = nil;
    self->_scrollView.clearsContextBeforeDrawing = YES;
    self->_scrollView.delegate = self;
    self->_scrollView.showsHorizontalScrollIndicator = NO;
    self->_scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
    [self addSubview:self->_scrollView];
    
    self->_selectionIndicator = [[OUIInspectorOptionWheelSelectionIndicator alloc] init];
    self->_selectionIndicator.layer.zPosition = 1;
    [self addSubview:self->_selectionIndicator];
    
    self->_items = [[NSMutableArray alloc] init];
    [self setNeedsLayout];
    
    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (void)dealloc;
{
    [_scrollView release];
    [_selectionIndicator release];
    [_items release];
    [_selectedItem release];
    [super dealloc];
}

- (OUIInspectorOptionWheelItem *)addItemWithImage:(UIImage *)image value:(id)value;
{
    OBPRECONDITION(image);
    
    OUIInspectorOptionWheelItem *item = [[OUIInspectorOptionWheelItem alloc] init];
    item.value = value;
    [item setImage:image forState:UIControlStateNormal];
    [item addTarget:self action:@selector(_selectOptionWheelItem:) forControlEvents:UIControlEventTouchUpInside];
    [_items addObject:item];
    [item release];
    
    [_scrollView setNeedsLayout];
    
    if (!_selectedItem) {
        _selectedItem = [item retain];
        [self _snapToSelectionAnimated:NO];
    }
        
    return item;
}

- (OUIInspectorOptionWheelItem *)addItemWithImageNamed:(NSString *)imageName value:(id)value;
{
    return [self addItemWithImage:[UIImage imageNamed:imageName] value:value];
}

@synthesize items = _items;
- (void)setItems:(NSArray *)items;
{
    if (OFISEQUAL(_items, items))
        return;
    
    [_selectedItem release];
    _selectedItem = nil;
    
    // Not animating between partial changes of items... that might be cool.
    [_items makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [_items release];
    _items = [[NSMutableArray alloc] initWithArray:items];

    // The caller needs to tell us where to go, though this could leave us snapped.
    [_selectedItem release];
    _selectedItem = nil;
    
    [_scrollView setNeedsLayout];
    [self setNeedsLayout];
}

- (id)selectedValue;
{
    return _selectedItem.value;
}

- (void)setSelectedValue:(id)value;
{
    [self setSelectedValue:value animated:YES];
}

- (void)setSelectedValue:(id)value animated:(BOOL)animated;
{
    for (OUIInspectorOptionWheelItem *item in _items) {
        if (OFISEQUAL(value, item.value)) {
            [_selectedItem release];
            _selectedItem = [item retain];
            
            [self _snapToSelectionAnimated:animated];
            return;
        }
    }
}

#pragma mark -
#pragma mark UIScrollViewDelegate

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate;
{
    if (!decelerate)
        [self _selectClosestItemAndSendAction]; // otherwise wait until -scrollViewDidEndDecelerating:
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;
{
    [self _selectClosestItemAndSendAction];
}

#pragma mark -
#pragma mark UIView subclass

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    OUIInspectorWellDrawOuterShadow(ctx, bounds, YES/*rounded*/);
    
    // Fill the gradient
    CGContextSaveGState(ctx);
    {
        OUIInspectorWellAddPath(ctx, bounds, YES/*rounded*/);
        CGContextClip(ctx);
        
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
        CGShadingRef shading = CGShadingCreateAxial(colorSpace, bounds.origin, CGPointMake(CGRectGetMaxX(bounds), CGRectGetMinY(bounds)), BackgroundShadingFunction, NO, NO);
        CGColorSpaceRelease(colorSpace);
        CGContextDrawShading(ctx, shading);
        CGShadingRelease(shading);
    }
    CGContextRestoreGState(ctx);

    OUIInspectorWellDrawBorderAndInnerShadow(ctx, bounds, YES/*rounded*/);
}

- (void)layoutSubviews;
{
    CGRect bounds = self.bounds;
    
    _scrollView.frame = CGRectInset(bounds, 1, 1);

    CGRect indicatorFrame = _selectionIndicator.frame;
    _selectionIndicator.frame = CGRectMake(CGRectGetMidX(bounds) - CGRectGetWidth(indicatorFrame)/2,
                                           CGRectGetMinY(bounds), indicatorFrame.size.width, indicatorFrame.size.height);
    [_selectionIndicator updateColor];
}

#pragma mark -
#pragma mark Private

- (OUIInspectorOptionWheelItem *)_closestItemToCenter;
{
    CGRect bounds = self.bounds;
    CGPoint center = [self convertPoint:CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds)) toView:_scrollView];
    
    OUIInspectorOptionWheelItem *closestItem = nil;
    CGFloat closestDistance = 0;
    
    for (OUIInspectorOptionWheelItem *item in _items) {
        OBASSERT(item.superview == _scrollView);
        
        CGFloat distance = fabs(CGRectGetMidX(item.frame) - center.x);
        if (!closestItem || distance < closestDistance) {
            closestItem = item;
            closestDistance = distance;
        }
    }
    
    return closestItem;
}

- (void)_snapToSelectionAnimated:(BOOL)animated;
{
    if (!_selectedItem)
        return;
    
    CGRect snapFrame = _selectedItem.frame;
    CGFloat offsetX = CGRectGetMinX(snapFrame) - _scrollView.contentInset.left;
    
    [_scrollView setContentOffset:CGPointMake(offsetX, 0) animated:animated];
}

- (void)_selectClosestItemAndSendAction;
{
    [_selectedItem release];
    _selectedItem = [[self _closestItemToCenter] retain];
    
    [self _snapToSelectionAnimated:YES];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)_selectOptionWheelItem:(id)sender;
{
    OBPRECONDITION([sender isKindOfClass:[OUIInspectorOptionWheelItem class]]);
    OUIInspectorOptionWheelItem *optionWheelItem = sender;
    self.selectedValue = optionWheelItem.value;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end
