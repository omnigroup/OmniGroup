// Copyright 1997-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSScrollView-OAExtensions.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "NSView-OAExtensions.h"
#import "OADocumentPositioningView.h"

RCS_ID("$Id$")

@implementation NSScrollView (OAExtensions)

- (void)freeGStates;
{
    [self releaseGState];
    [[self contentView] releaseGState];
}

- (NSImageAlignment)documentViewAlignment;
{
    NSView *documentView;
    
    // if the document view is a positioning view, return its document view alignment; otherwise return bottom-left alignment (because that's the behavior you get if we aren't overriding it)
    documentView = [self documentView];
    if ([documentView isKindOfClass:[OADocumentPositioningView class]])
        return [(OADocumentPositioningView *)documentView documentViewAlignment];
    else
        return NSImageAlignBottomLeft;
}

- (void)setDocumentViewAlignment:(NSImageAlignment)value;
{
    OADocumentPositioningView *positioningView;
    
    // grab the document view
    positioningView = (OADocumentPositioningView *)[self documentView];
    
    // if it's not a positioning view, insert one
    if (![positioningView isKindOfClass:[OADocumentPositioningView class]]) {
        NSView *oldDocumentView;
        
        oldDocumentView = [positioningView retain];	// retain the old document view so it won't disappear while we're inserting the positining view into the view hierarchy
        positioningView = [[OADocumentPositioningView alloc] initWithFrame:[[self contentView] bounds]];
        [self setDocumentView:positioningView];
        [positioningView setDocumentView:oldDocumentView];
        [oldDocumentView release];
        [positioningView release];
    }

    [positioningView setDocumentViewAlignment:value];
}

// Overrides of NSView (OAExtensions)

- (void)scrollToTop;
{
    [[self documentView] scrollToTop];
}

- (void)scrollToEnd;
{
    [[self documentView] scrollToEnd];
}

- (void)scrollDownByPages:(float)pagesToScroll;
{
    [[self documentView] scrollDownByPages:pagesToScroll];
}

- (void)scrollDownByLines:(float)linesToScroll;
{
    [[self documentView] scrollDownByLines:linesToScroll];
}

- (void)scrollDownByPercentage:(float)percentage;
{
    [[self documentView] scrollDownByPercentage:percentage];
}

- (void)scrollDownByAdjustedPixels:(float)pixels;
{
    [[self documentView] scrollDownByAdjustedPixels:pixels];
}


- (void)scrollRightByPages:(float)pagesToScroll;
{
    [[self documentView] scrollRightByPages:pagesToScroll];
}

- (void)scrollRightByLines:(float)linesToScroll;
{
    [[self documentView] scrollRightByLines:linesToScroll];
}

- (void)scrollRightByPercentage:(float)percentage;
{
    [[self documentView] scrollRightByPercentage:percentage];
}

- (void)scrollRightByAdjustedPixels:(float)pixels;
{
    [[self documentView] scrollRightByAdjustedPixels:pixels];
}

- (NSPoint)scrollPosition;
{
    return [[self documentView] scrollPosition];
}

- (void)setScrollPosition:(NSPoint)scrollPosition;
{
    [[self documentView] setScrollPosition:scrollPosition];
}

- (NSPoint)scrollPositionAsPercentage;
{
    return [[self documentView] scrollPositionAsPercentage];
}

- (void)setScrollPositionAsPercentage:(NSPoint)scrollPosition;
{
    [[self documentView] setScrollPositionAsPercentage:scrollPosition];
}

- (float)fraction;
{
    return [[self documentView] fraction];
}

- (void)setFraction:(float)fraction;
{
    [[self documentView] setFraction:fraction];
}

@end
