// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorOptionWheel.h>

#import <OmniUI/OUIInspectorOptionWheelItem.h>
#import <OmniUI/OUIInspectorOptionWheelSelectionIndicator.h>
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
- (UIImage *)_imageWithHighlight:(UIImage *)baseImage;
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
    
    const CGFloat kItemSpacingX = 13;
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
{
    OUIInspectorOptionWheelSelectionIndicator *_selectionIndicator;
    OUIInspectorOptionWheelScrollView *_scrollView;
    NSMutableArray *_items;
    OUIInspectorOptionWheelItem *_selectedItem; // might be animating to this, but not there yet
    UIView *_leftShieldView;
    UIView *_rightShieldView;
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
    self->_selectionIndicator.userInteractionEnabled = NO;
    [self addSubview:self->_selectionIndicator];
    
    self->_items = [[NSMutableArray alloc] init];
    [self setNeedsLayout];

    self->_leftShieldView = [[UIView alloc] init];
    self->_leftShieldView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    self->_leftShieldView.userInteractionEnabled = NO;
    [self addSubview:self->_leftShieldView];

    self->_rightShieldView = [[UIView alloc] init];
    self->_rightShieldView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    self->_rightShieldView.userInteractionEnabled = NO;
    [self addSubview:self->_rightShieldView];

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
    _scrollView.delegate = nil;
}

- (OUIInspectorOptionWheelItem *)addItemWithImage:(UIImage *)image value:(id)value;
{
    OBPRECONDITION(image);
    
    OUIInspectorOptionWheelItem *item = [[OUIInspectorOptionWheelItem alloc] init];
    item.value = value;
    item.contentMode = UIViewContentModeCenter;
    [item setImage:image forState:UIControlStateNormal];
    if (_showHighlight)
        [item setImage:[self _imageWithHighlight:image] forState:UIControlStateSelected];
    [item addTarget:self action:@selector(_selectOptionWheelItem:) forControlEvents:UIControlEventTouchUpInside];
    [_items addObject:item];
    
    [_scrollView setNeedsLayout];
    
    if (!_selectedItem) {
        _selectedItem = item;
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
    
    _selectedItem = nil;
    
    // Not animating between partial changes of items... that might be cool.
    [_items makeObjectsPerformSelector:@selector(removeFromSuperview)];
    _items = [[NSMutableArray alloc] initWithArray:items];

    // The caller needs to tell us where to go, though this could leave us snapped.
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
            if (_showHighlight)
                _selectedItem.selected = NO;
            _selectedItem = item;
            if (_showHighlight)
                _selectedItem.selected = YES;

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


- (void)layoutSubviews;
{
    CGRect bounds = self.bounds;
    
    _scrollView.frame = CGRectInset(bounds, 1, 1);

    const CGFloat kItemSpacingX = 6;
    const CGFloat kItemSpacingY = 3;
    const CGFloat itemSize = CGRectGetHeight(bounds) - 2*kItemSpacingY;

    _selectionIndicator.frame = CGRectMake(CGRectGetMidX(bounds) - itemSize/2 - kItemSpacingX,
                                           CGRectGetMinY(bounds), itemSize + 2*kItemSpacingX, _scrollView.frame.size.height);

    _leftShieldView.frame = CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds), CGRectGetMidX(bounds) - itemSize/2 - kItemSpacingX, _scrollView.frame.size.height);
    _rightShieldView.frame = CGRectMake(CGRectGetMaxX(_selectionIndicator.frame), CGRectGetMinY(bounds), CGRectGetMidX(bounds) - itemSize/2 - kItemSpacingX, _scrollView.frame.size.height);

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

    // make sure our items have frames before we try'n layout based upon them.
    [self layoutIfNeeded];

    CGRect snapFrame = _selectedItem.frame;
    CGFloat offsetX = CGRectGetMinX(snapFrame) - _scrollView.contentInset.left;

    [_scrollView setContentOffset:CGPointMake(offsetX, 0) animated:animated];
}

- (void)_selectClosestItemAndSendAction;
{
    if (_showHighlight)
        _selectedItem.selected = NO;
    _selectedItem = [self _closestItemToCenter];
    if (_showHighlight)
        _selectedItem.selected = YES;
    
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

@synthesize showHighlight = _showHighlight;
- (UIImage *)_imageWithHighlight:(UIImage *)baseImage;
{
    CGFloat blur = 4;
    
    UIImage *result = nil;
    UIGraphicsBeginImageContextWithOptions(baseImage.size, NO, 0.0); {
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGRect baseDrawingRect = CGRectMake(0, 0, baseImage.size.width, baseImage.size.height);
        
        // flipping
        CGContextTranslateCTM(context, 0.0, baseImage.size.height);
        CGContextScaleCTM(context, 1.0, -1.0);
        
        // draw original image with a shadow
        CGContextSetShadowWithColor(context, CGSizeMake(0, 0), blur, [UIColor colorWithRed:0 green:0.3 blue:0.88 alpha:1].CGColor);
        CGContextDrawImage(context, baseDrawingRect, baseImage.CGImage);
        
        result =  UIGraphicsGetImageFromCurrentImageContext();
    } UIGraphicsEndImageContext();
    
    return result;
}

@end
