// Copyright 1997-2006, 2010, 2014 Omni Development, Inc.  All rights reserved.
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

- (void)scrollDownByPages:(CGFloat)pagesToScroll;
{
    [[self documentView] scrollDownByPages:pagesToScroll];
}

- (void)scrollDownByLines:(CGFloat)linesToScroll;
{
    [[self documentView] scrollDownByLines:linesToScroll];
}

- (void)scrollDownByPercentage:(CGFloat)percentage;
{
    [[self documentView] scrollDownByPercentage:percentage];
}

- (void)scrollDownByAdjustedPixels:(CGFloat)pixels;
{
    [[self documentView] scrollDownByAdjustedPixels:pixels];
}


- (void)scrollRightByPages:(CGFloat)pagesToScroll;
{
    [[self documentView] scrollRightByPages:pagesToScroll];
}

- (void)scrollRightByLines:(CGFloat)linesToScroll;
{
    [[self documentView] scrollRightByLines:linesToScroll];
}

- (void)scrollRightByPercentage:(CGFloat)percentage;
{
    [[self documentView] scrollRightByPercentage:percentage];
}

- (void)scrollRightByAdjustedPixels:(CGFloat)pixels;
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

- (CGFloat)fraction;
{
    return [[self documentView] fraction];
}

- (void)setFraction:(CGFloat)fraction;
{
    [[self documentView] setFraction:fraction];
}

@end
