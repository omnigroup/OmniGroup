// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISegmentedControl.h>

#import <OmniUI/OUIInspectorButton.h>
#import <OmniUI/OUISegmentedControlButton.h>
#import <OmniFoundation/OFNull.h>
#import "OUIParameters.h"


RCS_ID("$Id$");

static const CGFloat kButtonWidth = 57;

@interface OUISegmentedControl () <UIPointerInteractionDelegate>
- (void)_segmentPressed:(OUISegmentedControlButton *)segment;
@end

@implementation OUISegmentedControl
{
    NSMutableArray *_segments;
}

+ (CGFloat)buttonHeight;
{
    return [OUIInspectorButton buttonHeight];
}

static id _commonInit(OUISegmentedControl *self)
{
    self.opaque = NO;
    self.backgroundColor = nil;
    self->_segments = [[NSMutableArray alloc] init];
    return self;
}

- initWithFrame:(CGRect)frame;
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

- (OUISegmentedControlButton *)addSegmentWithImage:(UIImage *)image representedObject:(id)representedObject;
{
    OBPRECONDITION(image);
    
    OUISegmentedControlButton *segment = [OUISegmentedControlButton buttonWithType:UIButtonTypeCustom];
    if (self.segmentFont != nil)
        segment.titleLabel.font = self.segmentFont;
    segment.image = image;
    segment.representedObject = representedObject;
    segment.enabled = self.enabled;
    [segment addTarget:self action:@selector(_segmentPressed:)];
    [_segments addObject:segment];
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
    return segment;
}

- (OUISegmentedControlButton *)addSegmentWithImage:(UIImage *)image;
{
    return [self addSegmentWithImage:image representedObject:nil];
}

- (OUISegmentedControlButton *)addSegmentWithText:(NSString *)text representedObject:(id)representedObject;
{
    OUISegmentedControlButton *segment = [OUISegmentedControlButton buttonWithType:UIButtonTypeCustom];
    if (self.segmentFont != nil)
        segment.titleLabel.font = self.segmentFont;
    [segment setTitle:text forState:UIControlStateNormal];
    segment.representedObject = representedObject;
    [segment addTarget:self action:@selector(_segmentPressed:)];
    [_segments addObject:segment];
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
    return segment;
}

- (OUISegmentedControlButton *)addSegmentWithText:(NSString *)text;
{
    return [self addSegmentWithText:text representedObject:nil];
}

- (void)removeAllSegments;
{
    for (UIView *view in _segments)
        [view removeFromSuperview];
    [_segments removeAllObjects];
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}

- (void)setAllowsMulitpleSelection:(BOOL)flag;
{
    if (_allowsMultipleSelection == flag)
        return;
    
    _allowsMultipleSelection = flag;
    
    if (!_allowsMultipleSelection) {
        // Clear any extra selected items after the first
        OUISegmentedControlButton *firstSelectedSegment = self.selectedSegment;
        for (OUISegmentedControlButton *segment in _segments)
            if (segment.selected && firstSelectedSegment != segment)
                segment.selected = NO;
    }
}

- (void)setSizesSegmentsToFit:(BOOL)flag;
{
    if (_sizesSegmentsToFit == flag)
        return;
    _sizesSegmentsToFit = flag;
    [self setNeedsLayout];
}

- (OUISegmentedControlButton *)selectedSegment;
{
    for (OUISegmentedControlButton *segment in _segments)
        if (segment.selected)
            return segment;
    return nil;
}
- (void)setSelectedSegment:(OUISegmentedControlButton *)selectedSegment;
{
    for (OUISegmentedControlButton *segment in _segments)
        segment.selected = (selectedSegment == segment);
}

- (OUISegmentedControlButton *)firstSegment;
{
    if ([_segments count] > 0)
        return [_segments objectAtIndex:0];
    return nil;
}

- (void)setSelectedSegmentIndex:(NSInteger)index;
{
    NSInteger counter = 0;
    for (OUISegmentedControlButton *segment in _segments) {
        segment.selected = (counter == index);
        counter++;
    }
}

- (NSInteger)selectedSegmentIndex;
{
    NSInteger counter = 0;
    for (OUISegmentedControlButton *segment in _segments) {
        if (segment.selected)
            return counter;
        counter++;
    }
    return UISegmentedControlNoSegment;
}

- (void)setSelectedSegmentsIndexSet:(NSIndexSet *)indexSet;
{
    OBASSERT_IF(!self.allowsMultipleSelection, indexSet.count == 0 || indexSet.count == 1);
    [_segments enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        OUISegmentedControlButton *segment = obj;
        segment.selected = [indexSet containsIndex:idx];
    }];
}

- (NSIndexSet *)selectedSegmentsIndexSet;
{
    NSMutableIndexSet *selectedSegments = [NSMutableIndexSet indexSet];
    [_segments enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        OUISegmentedControlButton *segment = obj;
        if (segment.selected)
            [selectedSegments addIndex:idx];
    }];
    return selectedSegments;
}

- (NSUInteger)segmentCount;
{
    return [_segments count];
}

- (NSUInteger)indexOfSegment:(OUISegmentedControlButton *)segment;
{
    return [_segments indexOfObjectIdenticalTo:segment];
}

- (OUISegmentedControlButton *)segmentAtIndex:(NSUInteger)segmentIndex;
{
    NSUInteger segmentCount = [_segments count];
    if (segmentIndex >= segmentCount) {
        OBASSERT_NOT_REACHED("Bad index passed in");
        return nil;
    }
    return [_segments objectAtIndex:segmentIndex];
}

- (OUISegmentedControlButton *)segmentWithRepresentedObject:(id)object;
{
    for (OUISegmentedControlButton *segment in _segments) {
        if (OFISEQUAL(object, segment.representedObject))
            return segment;
    }
    return nil;
}

- (void)setEnabled:(BOOL)yn;
{
    super.enabled = yn;
    for (OUISegmentedControlButton *button in _segments)
        [button setEnabled:yn];
}

#pragma mark -
#pragma mark UIView subclass

- (CGSize)intrinsicContentSize;
{
    return (CGSize){.height = [[self class] buttonHeight], .width = [_segments count] * kButtonWidth};
}

- (void)layoutSubviews;
{
    OBPRECONDITION([_segments count] >= 2); // Else, why are you using a segmented control at all...

    CGRect bounds = self.bounds;
    
    // Don't go totally insane if we only have one button, but it won't look good.

    NSInteger buttonCount = [_segments count];
    
    CGFloat xOffset, buttonWidth;
    
    if (_sizesSegmentsToFit) {
        xOffset = CGRectGetMinX(bounds);
        buttonWidth = CGRectGetWidth(bounds) / buttonCount;
    } else {
        CGFloat totalWidth = buttonCount * kButtonWidth;
        xOffset = CGRectGetMinX(bounds) + floor((CGRectGetWidth(bounds) - totalWidth) / 2);
        buttonWidth = kButtonWidth;
    }
    
    
    for (NSInteger buttonIndex = 0; buttonIndex < buttonCount; buttonIndex++) {
        OUISegmentedControlButton *button = [_segments objectAtIndex:buttonIndex];
        
        if (buttonIndex == 0)
            button.buttonPosition = OUISegmentedControlButtonPositionLeft;
        else if (buttonIndex == buttonCount - 1)
            button.buttonPosition = OUISegmentedControlButtonPositionRight;
        else
            button.buttonPosition = OUISegmentedControlButtonPositionCenter;
        
        // Take care to fill the whole area and deal with leftover fractions of pixels
#define BUTTON_LEFT_X(n) floor(xOffset + (n) * buttonWidth)
        
        CGRect buttonFrame;
        buttonFrame.origin.x = BUTTON_LEFT_X(buttonIndex);
        buttonFrame.origin.y = CGRectGetMinY(bounds);
        buttonFrame.size.width = BUTTON_LEFT_X(buttonIndex + 1) - BUTTON_LEFT_X(buttonIndex);
        buttonFrame.size.height = self.bounds.size.height;
        
        if (_sizesSegmentsToFit && (buttonIndex == buttonCount - 1)) {
            // Make sure the last button reaches all the way to the right edge
            buttonFrame.size.width = CGRectGetMaxX(bounds) - buttonFrame.origin.x;
        }
        
        button.frame = buttonFrame;
        if (button.superview != self)
            [self addSubview:button];
    }
}

- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    if (@available(iOS 13.4, *)) {
        [self addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];
    }
}

- (void)setSegmentFont:(UIFont *)font;
{
    OBPRECONDITION(font != nil);
    if ([font isEqual:_segmentFont])
        return;
    
    _segmentFont = font;
    for (OUISegmentedControlButton *segment in _segments)
        segment.titleLabel.font = font;
}

#pragma mark - UIPointerInteractionDelegate

- (nullable UIPointerRegion *)pointerInteraction:(UIPointerInteraction *)interaction regionForRequest:(UIPointerRegionRequest *)request defaultRegion:(UIPointerRegion *)defaultRegion API_AVAILABLE(ios(13.4));
{
    UIView *segment = [self hitTest:request.location withEvent:nil];
    OBASSERT([self indexOfSegment:(OUISegmentedControlButton *)segment] != NSNotFound);
    return [UIPointerRegion regionWithRect:segment.frame identifier:segment];
}


- (nullable UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region API_AVAILABLE(ios(13.4));
{
    UIView *segmentButton = OB_CHECKED_CAST(UIView, region.identifier);
    UIPointerHighlightEffect *segmentHighlightEffect = [UIPointerHighlightEffect effectWithPreview:[[UITargetedPreview alloc] initWithView:segmentButton]];
    return [UIPointerStyle styleWithEffect:segmentHighlightEffect shape:nil];
}

#pragma mark - UIAccessibility

- (BOOL)isAccessibilityElement;
{
    // We aren't an accessibility element - our button subviews are
    return NO;
}

#pragma mark - Private

- (void)_segmentPressed:(OUISegmentedControlButton *)segment;
{
    if (_allowsMultipleSelection) {
        segment.selected = !segment.selected;
    } else if (_allowsEmptySelection && self.selectedSegment == segment) {
        self.selectedSegment = nil;
    } else {
        self.selectedSegment = segment;
    }
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end
