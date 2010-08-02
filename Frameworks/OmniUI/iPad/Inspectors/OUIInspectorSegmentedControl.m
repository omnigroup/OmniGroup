// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSegmentedControl.h>
#import <OmniUI/OUIInspectorSegmentedControlButton.h>
#import <UIKit/UIKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFNull.h>

RCS_ID("$Id$");

static const CGFloat kButtonWidth = 57;
static const CGFloat kButtonHeight = 38;

@interface OUIInspectorSegmentedControl (/*Private*/)
- (void)_segmentPressed:(id)sender;
@end

@implementation OUIInspectorSegmentedControl

static id _commonInit(OUIInspectorSegmentedControl *self)
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

- (void)dealloc;
{
    [_segments release];
    [super dealloc];
}

- (OUIInspectorSegmentedControlButton *)addSegmentWithImageNamed:(NSString *)imageName representedObject:(id)representedObject;
{
    OUIInspectorSegmentedControlButton *segment = [OUIInspectorSegmentedControlButton buttonWithType:UIButtonTypeCustom];
    segment.image = [UIImage imageNamed:imageName];
    segment.representedObject = representedObject;
    [segment addTarget:self action:@selector(_segmentPressed:) forControlEvents:UIControlEventTouchDown];
    [_segments addObject:segment];
    [self setNeedsLayout];
    return segment;
}

- (OUIInspectorSegmentedControlButton *)addSegmentWithImageNamed:(NSString *)imageName;
{
    return [self addSegmentWithImageNamed:imageName representedObject:nil];
}

- (OUIInspectorSegmentedControlButton *)addSegmentWithText:(NSString *)text representedObject:(id)representedObject;
{
    OUIInspectorSegmentedControlButton *segment = [OUIInspectorSegmentedControlButton buttonWithType:UIButtonTypeCustom];
    [segment setTitle:text forState:UIControlStateNormal];
    segment.representedObject = representedObject;
    [segment addTarget:self action:@selector(_segmentPressed:) forControlEvents:UIControlEventTouchDown];
    [_segments addObject:segment];
    [self setNeedsLayout];
    return segment;
}

- (OUIInspectorSegmentedControlButton *)addSegmentWithText:(NSString *)text;
{
    return [self addSegmentWithText:text representedObject:nil];
}

@synthesize sizesSegmentsToFit = _sizesSegmentsToFit;
- (void)setSizesSegmentsToFit:(BOOL)flag;
{
    if (_sizesSegmentsToFit == flag)
        return;
    _sizesSegmentsToFit = flag;
    [self setNeedsLayout];
}

- (OUIInspectorSegmentedControlButton *)selectedSegment;
{
    for (OUIInspectorSegmentedControlButton *segment in _segments)
        if (segment.selected)
            return segment;
    return nil;
}
- (void)setSelectedSegment:(OUIInspectorSegmentedControlButton *)selectedSegment;
{
    for (OUIInspectorSegmentedControlButton *segment in _segments)
        segment.selected = (selectedSegment == segment);
}

- (OUIInspectorSegmentedControlButton *)firstSegment;
{
    if ([_segments count] > 0)
        return [_segments objectAtIndex:0];
    return nil;
}

- (void)setSelectedSegmentIndex:(NSInteger)index;
{
    NSInteger counter = 0;
    for (OUIInspectorSegmentedControlButton *segment in _segments) {
        segment.selected = (counter == index);
        counter++;
    }
}

- (NSInteger)selectedSegmentIndex;
{
    NSInteger counter = 0;
    for (OUIInspectorSegmentedControlButton *segment in _segments) {
        if (segment.selected)
            return counter;
        counter++;
    }
    return UISegmentedControlNoSegment;
}

- (NSUInteger)segmentCount;
{
    return [_segments count];
}

- (OUIInspectorSegmentedControlButton *)segmentAtIndex:(NSUInteger)segmentIndex;
{
    NSUInteger segmentCount = [_segments count];
    if (segmentIndex >= segmentCount) {
        OBASSERT_NOT_REACHED("Bad index passed in");
        return nil;
    }
    return [_segments objectAtIndex:segmentIndex];
}

- (OUIInspectorSegmentedControlButton *)segmentWithRepresentedObject:(id)object;
{
    for (OUIInspectorSegmentedControlButton *segment in _segments) {
        if (OFISEQUAL(object, segment.representedObject))
            return segment;
    }
    return nil;
}

- (CGFloat)buttonHeight;
// Graffle subclasses this to keep the height from changing, though sizesToFit might make more sense
{
    return kButtonHeight;
}

- (void)setEnabled:(BOOL)yn;
{
    for (OUIInspectorSegmentedControlButton *button in _segments)
        [button setEnabled:yn];
}

#pragma mark -
#pragma mark UIView subclass
- (void)layoutSubviews;
{
    OBPRECONDITION([_segments count] >= 2); // Else, why are you using a segmented control at all...

    CGRect bounds = self.bounds;
    OBASSERT(bounds.size.height == [self buttonHeight]); // Make sure it is the right size in the xib. Or maybe we should add a -sizeThatFits...
    
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
        OUIInspectorSegmentedControlButton *button = [_segments objectAtIndex:buttonIndex];
        
        if (buttonIndex == 0)
            button.buttonPosition = OUIInspectorSegmentedControlButtonPositionLeft;
        else if (buttonIndex == buttonCount - 1)
            button.buttonPosition = OUIInspectorSegmentedControlButtonPositionRight;
        else
            button.buttonPosition = OUIInspectorSegmentedControlButtonPositionCenter;
        
        // Take care to fill the whole area and deal with leftover fractions of pixels
#define BUTTON_LEFT_X(n) floor(xOffset + (n) * buttonWidth)
        
        CGRect buttonFrame;
        buttonFrame.origin.x = BUTTON_LEFT_X(buttonIndex);
        buttonFrame.origin.y = CGRectGetMinY(bounds);
        buttonFrame.size.width = BUTTON_LEFT_X(buttonIndex + 1) - BUTTON_LEFT_X(buttonIndex);
        buttonFrame.size.height = [self buttonHeight];
        
        if (_sizesSegmentsToFit && (buttonIndex == buttonCount - 1)) {
            // Make sure the last button reaches all the way to the right edge
            buttonFrame.size.width = CGRectGetMaxX(bounds) - buttonFrame.origin.x;
        }
        
        button.frame = buttonFrame;
        if (button.superview != self)
            [self addSubview:button];
    }
}

- (void)setSegmentFont:(UIFont *)font;
{
    for (OUIInspectorSegmentedControlButton *segment in _segments)
        segment.titleLabel.font = font;
}

#pragma mark -
#pragma mark Private

- (void)_segmentPressed:(OUIInspectorSegmentedControlButton *)segment;
{
    self.selectedSegment = segment;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end
