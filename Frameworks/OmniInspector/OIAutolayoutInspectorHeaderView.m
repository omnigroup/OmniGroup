// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIAutolayoutInspectorHeaderView.h"

#import <OmniAppKit/OATrackingLoop.h>

RCS_ID("$Id$");

@interface OIAutolayoutInspectorHeaderView ()

@property (nonatomic, strong) IBOutlet NSLayoutConstraint *verticalCenteringConstraint;

@end

@implementation OIAutolayoutInspectorHeaderView

+ (CGFloat)contentHeight;
{
    return 24; //[[OIAppearance appearance] CGFloatForKeyPath:@"InspectorHeaderContentHeight"];
}

+ (CGFloat)separatorTopPadding;
{
    return 5; // [[OIAppearance appearance] CGFloatForKeyPath:@"InspectorHeaderSeparatorTopPadding"];
}

- (void)setDrawsSeparator:(BOOL)drawsSeparator;
{
    if (drawsSeparator == _drawsSeparator)
        return;
    
    _drawsSeparator = drawsSeparator;
    
    self.verticalCenteringConstraint.constant = -1 * [[self class] separatorTopPadding] / (drawsSeparator ? 1 : 2);
    [self invalidateIntrinsicContentSize];
}

#pragma mark - NSView subclass

#pragma mark Event handling

- (NSView *)hitTest:(NSPoint)aPoint;
{
    // We want all the clicks for ourselves!
    if (NSPointInRect(aPoint, [self frame])) {
        return self;
    }
    
    return [super hitTest:aPoint];
}

- (void)mouseDown:(NSEvent *)theEvent;
{
    [self.disclosureButton.cell setHighlighted:YES];

    OATrackingLoop *loop = [self trackingLoopForMouseDown:theEvent];
    loop.hysteresisSize = 5.0f;

    loop.dragged = ^(OATrackingLoop *loop) {
        // Hide inspector contents, grab drag image
//        NSPoint dragLocation = loop.currentMouseDraggedPointInView;
        
        NSLog(@"foo!");
        if (!loop.insideVisibleRect) {
        }
    };
    
    loop.up = ^(OATrackingLoop *loop){
        // Show inspector contents, move inspector
    };
    
    loop.shouldAutoscroll = ^(OATrackingLoop *loop){
        return YES;
    };
    
    [loop run];
}

- (void)mouseDragged:(NSEvent *)theEvent;
{
    NSPoint viewPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    BOOL inBounds = NSPointInRect(viewPoint, [self bounds]);
    [self.disclosureButton.cell setHighlighted:inBounds];
}

- (void)mouseUp:(NSEvent *)theEvent;
{
    [self.disclosureButton.cell setHighlighted:NO];
    
    NSPoint viewPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    BOOL inBounds = NSPointInRect(viewPoint, [self bounds]);
    
    if (inBounds) {
        [self.disclosureButton sendAction:self.disclosureButton.action to:self.disclosureButton.target];
    }
}

#pragma mark Layout

- (NSSize)intrinsicContentSize;
{
    CGFloat desiredHeight = [[self class] contentHeight];
    if (self.drawsSeparator)
        desiredHeight += [[self class] separatorTopPadding];
    
    return (NSSize){
        .width = NSViewNoInstrinsicMetric,
        .height = desiredHeight,
    };
}

#pragma mark Drawing

- (void)drawRect:(NSRect)dirtyRect;
{
    [super drawRect:dirtyRect];
    
    if (self.drawsSeparator == NO)
        return;
    
    CGFloat edgeInset = NSMinX(self.disclosureButton.frame);
    CGFloat height = 1.0f;
    CGFloat topPadding = [[self class] separatorTopPadding];
    
    NSRect separatorRect = (NSRect){
        .origin = (NSPoint){
            .x = edgeInset,
            .y = [self isFlipped] ? NSMinY(self.bounds) + topPadding : NSMaxY(self.bounds) - height - topPadding,
        },
        .size = (NSSize){
            .width = NSWidth(self.bounds) - 2 * edgeInset,
            .height = height,
        },
    };
    
    [[NSColor colorWithCalibratedHue:0 saturation:0 brightness:0.75 alpha:1] setFill];
    NSRectFill(separatorRect);
}

@end
