// Copyright 2013-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OASubtleScroller.h>
#import <AvailabilityMacros.h>


@implementation OASubtleScroller
{
    BOOL _visibleEdgeSpecified;
    NSRectEdge _specifiedVisibleEdge;
    NSColor *_scrollerBackgroundColor;
}

#pragma mark - API

- (BOOL)_subtleScrollerIsVertical;
{
    NSSize size = self.bounds.size;
    return size.width < size.height;
}

- (NSRectEdge)visibleEdge;
{
    if (_visibleEdgeSpecified)
        return _specifiedVisibleEdge;
    
    if ([self _subtleScrollerIsVertical])
        return (self.userInterfaceLayoutDirection == NSUserInterfaceLayoutDirectionRightToLeft) ? NSMaxXEdge : NSMinXEdge;
    else
        return self.isFlipped ? NSMinYEdge : NSMaxYEdge;
}

- (void)setVisibleEdge:(NSRectEdge)edge;
{
    _visibleEdgeSpecified = YES;
    _specifiedVisibleEdge = edge;
    
    [self setNeedsDisplay:YES];
}

- (void)setScrollerBackgroundColor:(NSColor *)scrollerBackgroundColor
{
    _scrollerBackgroundColor = scrollerBackgroundColor;
    
    [self setNeedsDisplay:YES];
}

- (NSColor *)scrollerBackgroundColor
{
    return _scrollerBackgroundColor;
}

#pragma mark - NSScroller subclass

+ (BOOL)isCompatibleWithOverlayScrollers;
{
    return self == [OASubtleScroller class];
}

- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag;
{
    if (_scrollerBackgroundColor != nil) {
        [_scrollerBackgroundColor setFill];
        NSRectFillUsingOperation(slotRect, NSCompositingOperationSourceOver);
    }

    static NSColor *edgeColor;
//    static NSGradient *edgeGradient;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        edgeColor = [[NSColor blackColor] colorWithAlphaComponent:0.25f];
//        edgeGradient = [[NSGradient alloc] initWithStartingColor:[NSColor clearColor] endingColor:edgeColor];
    });
    
    NSRect edgeRect;
    NSDivideRect(slotRect, &edgeRect, &(NSRect){}, 1.0f, self.visibleEdge);
    
    if (self.scrollerStyle == NSScrollerStyleOverlay) {
        // N.B. This method is only called for overlay scrollers if the user initiated a scrollwheel event while the cursor was in the scroller track. In that case, an additional line helps to separate the overlaid scroller from the content beneath it.
        [edgeColor setFill];
        NSRectFillUsingOperation(edgeRect, NSCompositingOperationSourceOver);
    }
}

@end
