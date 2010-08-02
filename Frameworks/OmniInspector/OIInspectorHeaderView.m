// Copyright 2002-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIInspectorHeaderView.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/OAAquaButton.h>
#import <OmniAppKit/NSAttributedString-OAExtensions.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>
#import "OIInspectorGroup.h"
#import "OITabbedInspector.h"  // For OITabbedInspectorUnifiedLookDefaultsKey
RCS_ID("$Id$")


@interface OIInspectorHeaderView (/*Private*/)
- (BOOL)_allowToggleExpandedness;
@end


@implementation OIInspectorHeaderView

typedef enum {
    OIInspectorNotKey = 0, OIInspectorIsKey = 1, OIInspectorKeyStatusCount,
} OIInspectorKeyStatus;
static NSString *OIInspectorHeaderImageKeyStatusNames[OIInspectorKeyStatusCount] = {@"Inactive", @"Active"};

typedef enum {
    OIInspectorHeaderImageStateNormal, OIInspectorHeaderImageStatePressed, OIInspectorHeaderImageStateCount,
} OIInspectorHeaderImageState;
static NSString *OIInspectorHeaderImageStateNames[OIInspectorHeaderImageStateCount] = {@"", @"Pressed"};

// NSControlTint enum is not sequential the way we want here...
typedef enum {
    OIInspectorHeaderImageTintBlue, OIInspectorHeaderImageTintGraphite, OIInspectorHeaderImageTintCount,
} OIInspectorHeaderImageTint;
static NSString *OIInspectorHeaderImageTintNames[OIInspectorHeaderImageTintCount] = {@"-Ice", @"-Graphite"};

typedef enum {
    OIInspectorCloseButtonStateNormal, OIInspectorCloseButtonStateRollover, OIInspectorCloseButtonStatePressed, OIInspectorCloseButtonStateCount
} OIInspectorCloseButtonState;
static NSString *OIInspectorCloseButtonStateNames[OIInspectorCloseButtonStateCount] = {@"-Normal", @"-Rollover", @"-Pressed"};

static NSImage *_headerImages[OIInspectorKeyStatusCount][OIInspectorHeaderImageStateCount];

static NSImage *_expandedImage, *_collapsedImage;

static NSImage *_closeButtonImages[OIInspectorHeaderImageTintCount][OIInspectorCloseButtonStateCount];

static NSDictionary *_textAttributes, *_keyEquivalentAttributes;

static BOOL omitTextAndStateWhenCollapsed;

static NSGradient *unifiedGradientKey, *unifiedGradientNonKey;

+ (void)initialize;
{
    OBINITIALIZE;

    {
        OIInspectorKeyStatus keyStatusIndex;
        for (keyStatusIndex = 0; keyStatusIndex < OIInspectorKeyStatusCount; keyStatusIndex++) {
            OIInspectorHeaderImageState stateIndex;
            for (stateIndex = 0; stateIndex < OIInspectorHeaderImageStateCount; stateIndex++) {
                NSString *imageName = [NSString stringWithFormat:@"OITitlebar%@%@", OIInspectorHeaderImageKeyStatusNames[keyStatusIndex], OIInspectorHeaderImageStateNames[stateIndex]];
                _headerImages[keyStatusIndex][stateIndex] = [[NSImage imageNamed:imageName inBundle:[OIInspectorHeaderView bundle]] retain];
		OBASSERT(_headerImages[keyStatusIndex][stateIndex]);
            }
        }
    }

    {
        OIInspectorHeaderImageTint tintIndex;
        for (tintIndex = 0; tintIndex < OIInspectorHeaderImageTintCount; tintIndex++) {
            OIInspectorCloseButtonState stateIndex;
            for (stateIndex = 0; stateIndex < OIInspectorCloseButtonStateCount; stateIndex++) {
                NSString *imageName = [NSString stringWithFormat:@"OIWindowSmallCloseBox%@%@", OIInspectorCloseButtonStateNames[stateIndex], OIInspectorHeaderImageTintNames[tintIndex]];
                _closeButtonImages[tintIndex][stateIndex] = [[NSImage imageNamed:imageName inBundle:[OIInspectorHeaderView bundle]] retain];
		OBASSERT(_closeButtonImages[tintIndex][stateIndex]);
            }
        }
    }

    _expandedImage = [[NSImage imageNamed:@"OIExpanded" inBundle:[OIInspectorHeaderView bundle]] retain];
    OBASSERT(_expandedImage);
    _collapsedImage = [[NSImage imageNamed:@"OICollapsed" inBundle:[OIInspectorHeaderView bundle]] retain];
    OBASSERT(_collapsedImage);

    _textAttributes = [[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:[NSFont labelFontSize]], NSFontAttributeName, nil] retain];
    _keyEquivalentAttributes = [[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:[NSFont labelFontSize]], NSFontAttributeName, [NSColor darkGrayColor], NSForegroundColorAttributeName, nil] retain];

    omitTextAndStateWhenCollapsed = [[NSUserDefaults standardUserDefaults] boolForKey:@"OmitTextAndStateWhenCollapsed"];
    
    unifiedGradientKey = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.77f alpha:1.0f] endingColor:[NSColor colorWithCalibratedWhite:.59f alpha:1.0f]];
    unifiedGradientNonKey = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.91f alpha:1.0f] endingColor:[NSColor colorWithCalibratedWhite:.81f alpha:1.0f]];
    
}

- (void)setTitle:(NSString *)aTitle;
{
    if (title != aTitle) {
        [title release];
        title = [aTitle retain];
        [self setNeedsDisplay:YES];
    }
}

#define IMAGE_SIZE (13.0f)

- (void)setImage:(NSImage *)anImage;
{
    if (image != anImage) {
        // If the image is PDF, we don't want to uses it's native size (which might be too big).
        [anImage setScalesWhenResized:YES];
        [anImage setSize:NSMakeSize(IMAGE_SIZE, IMAGE_SIZE)];
        
        [image release];
        image = [anImage retain];
        [self setNeedsDisplay:YES];
    }
}

- (void)setKeyEquivalent:(NSString *)anEquivalent;
{
    if (keyEquivalent != anEquivalent) {
        [keyEquivalent release];
        keyEquivalent = [anEquivalent retain];
        [self setNeedsDisplay:YES];
    }
}

- (void)setExpanded:(BOOL)newState;
{
    if (isExpanded != newState) {
        isExpanded = newState;
        [self setNeedsDisplay:YES];
    }
}

- (void)setDelegate:(NSObject <OIInspectorHeaderViewDelegateProtocol> *)aDelegate;
{
    delegate = aDelegate;
}

// NSView subclass

- (BOOL)isFlipped;
{
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent;
{
    return YES;
}

- (void)resetCursorRects;
{
    if ([delegate headerViewShouldDisplayCloseButton:self]) {
        NSRect closeRect = NSMakeRect(NSMinX(_bounds) + 6.0f, NSMaxY(_bounds)-1.0f - 14.0f, 14.0f, 14.0f);    
        [self addTrackingRect:closeRect owner:self userData:NULL assumeInside:NO];
    }
}

- (void)viewDidMoveToWindow;
{
    [self resetCursorRects];
}

- (void)mouseEntered:(NSEvent *)theEvent;
{
    overClose = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)theEvent;
{
    overClose = NO;
    [self setNeedsDisplay:YES];
}

- (void)drawBackgroundImageForBounds:(NSRect)backgroundBounds inRect:(NSRect)dirtyRect;
{
    OIInspectorKeyStatus keyStatus = (OIInspectorKeyStatus)[[self window] isKeyWindow];
    OIInspectorHeaderImageState state = isClicking && [self _allowToggleExpandedness] && !overClose ? OIInspectorHeaderImageStatePressed : OIInspectorHeaderImageStateNormal;
    
#ifdef OITabbedInspectorUnifiedLookDefaultsKey
    if ([[NSUserDefaults standardUserDefaults] boolForKey:OITabbedInspectorUnifiedLookDefaultsKey]) {
        NSRect gradient = backgroundBounds;
        gradient.origin.y += 1;
        gradient.size.height -= 2;
        
        NSGradient *blend = keyStatus? unifiedGradientKey : unifiedGradientNonKey;
        [blend drawInRect:gradient angle:90];
        
        [[NSColor colorWithCalibratedWhite:(keyStatus) ? 0.86f : 0.91f alpha:1.0f] set];
        NSRectFill(NSMakeRect(0,0, backgroundBounds.size.width, 1));
        [[NSColor colorWithCalibratedWhite:(keyStatus) ? .25f : .53f  alpha:1.0f] set];
        NSRectFill(NSMakeRect(0,backgroundBounds.size.height-1, backgroundBounds.size.width, 1));
        return;
    }
#endif
    
    NSImage *backgroundImage = _headerImages[keyStatus][state];
    
    // Kludge: Don't stretch the bottom 1px of the header image, because it's a hairline instead of a gradient. Might want to do this a different way.
    NSSize gradientSize = [backgroundImage size];
    if (gradientSize.height < backgroundBounds.size.height) {
        NSRect gradient, hairline, hairline2;
        NSDivideRect(backgroundBounds, &hairline, &gradient, 1.0f, NSMinYEdge);
        NSDivideRect(gradient, &hairline2, &gradient, 1.0f, NSMaxYEdge);
        [backgroundImage drawFlippedInRect:gradient fromRect:(NSRect){{0,1},{gradientSize.width,gradientSize.height-2}} operation:NSCompositeCopy];
        if (NSIntersectsRect(hairline, dirtyRect))
            [backgroundImage drawFlippedInRect:hairline fromRect:(NSRect){{0,gradientSize.height-1},{gradientSize.width,1}} operation:NSCompositeCopy];
        if (NSIntersectsRect(hairline2, dirtyRect))
            [backgroundImage drawFlippedInRect:hairline2 fromRect:(NSRect){{0,0},{gradientSize.width,1}} operation:NSCompositeCopy];
    } else {
        [backgroundImage drawFlippedInRect:backgroundBounds operation:NSCompositeCopy];
    }
}

- (void)drawRect:(NSRect)aRect;
{
    BOOL drawAll = isExpanded || !omitTextAndStateWhenCollapsed;
    OIInspectorHeaderImageTint imageTint = ([NSColor currentControlTint] == NSBlueControlTint) ? OIInspectorHeaderImageTintBlue : OIInspectorHeaderImageTintGraphite;
    
    if ([delegate headerViewShouldDisplayCloseButton:self]) {
        NSPoint closeImagePoint = NSMakePoint(NSMinX(_bounds) + 6.0f, NSMaxY(_bounds)-1.0f);
        NSImage *closeImage = _closeButtonImages[imageTint][clickingClose ? OIInspectorCloseButtonStatePressed : (overClose ? OIInspectorCloseButtonStateRollover : OIInspectorCloseButtonStateNormal)];
        
        [closeImage compositeToPoint:closeImagePoint operation:NSCompositeSourceOver];
    }
    
    CGFloat nextElementX = NSMinX(_bounds) + 26.0f;
    if (drawAll && [self _allowToggleExpandedness]) {
        NSImage *disclosureImage = isExpanded ? _expandedImage : _collapsedImage;
        NSPoint disclosureImagePoint = NSMakePoint(nextElementX, NSMaxY(_bounds)-2.0f);

        [disclosureImage compositeToPoint:disclosureImagePoint operation:NSCompositeSourceOver];

        if (isClicking && !overClose && !isDragging) // our triangle images are 100% black, but about 50% opaque, so we just draw it again over itself
            [disclosureImage compositeToPoint:disclosureImagePoint operation:NSCompositeSourceOver fraction:0.6666f];

        nextElementX += 20.0f;
    }
    
    if (image != nil) {
        NSGraphicsContext *currentContext = [NSGraphicsContext currentContext];
        CGContextRef cgContext = [currentContext graphicsPort];

        CGContextSaveGState(cgContext);
        CGContextTranslateCTM(cgContext, nextElementX, NSMaxY(_bounds)-2.0f);
        CGContextScaleCTM(cgContext, 1.0f, -1.0f);
        [image drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f];
        CGContextRestoreGState(cgContext);
        
        nextElementX += 20.0f;
    }
    
    CGFloat keyEquivalentWidth;
    if ([NSString isEmptyString:keyEquivalent])
        keyEquivalentWidth = 0.0f;
    else
        keyEquivalentWidth = [keyEquivalent sizeWithAttributes:_keyEquivalentAttributes].width + 5.0f;
    
    if (drawAll) {
        NSRect rect = NSMakeRect(nextElementX, NSMinY(_bounds), NSMaxX(_bounds) - nextElementX - 5.0f - keyEquivalentWidth, NSHeight(_bounds));
        if ([title isKindOfClass:[NSAttributedString class]]) {
            [(NSAttributedString *)title drawInRectangle:rect alignment:NSLeftTextAlignment verticallyCentered:YES];
        } else {
            NSAttributedString *attr = [[NSAttributedString alloc] initWithString:title attributes:_textAttributes];
            [attr drawInRectangle:rect alignment:NSLeftTextAlignment verticallyCentered:YES];
            [attr release];
        }
    }

    [keyEquivalent drawAtPoint:NSMakePoint(NSMaxX(_bounds) - keyEquivalentWidth, NSMinY(_bounds) + 1.0f) withAttributes:_keyEquivalentAttributes];
}

- (void)mouseDown:(NSEvent *)theEvent;
{
    NSPoint click = [NSEvent mouseLocation];
    NSWindow *window = [self window];
    NSRect windowFrame = [window frame];
    NSSize windowOriginOffset = NSMakeSize(click.x - windowFrame.origin.x, click.y - windowFrame.origin.y);
    NSRect hysterisisRect = NSMakeRect(click.x - 3.0f, click.y - 3.0f, 6.0f, 6.0f);
    NSRect closeRect = NSMakeRect(NSMinX(_bounds) + 6.0f, NSMaxY(_bounds)-1.0f - 14.0f, 14.0f, 14.0f);
    NSPoint newTopLeft = NSMakePoint(NSMinX(windowFrame), NSMaxY(windowFrame));
    CGFloat dragWindowHeight = 0.0f;
    BOOL isInOriginalFrame = NSPointInRect([theEvent locationInWindow], [self frame]);  // don't collapse if the mousedown is not within the header frame (as when this is called from tab area)
    
    click = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    
    isDragging = NO;
    isClicking = YES;
    overClose = clickingClose = [delegate headerViewShouldDisplayCloseButton:self] && NSMouseInRect(click, closeRect, NO);
    [self display];
    
    do {
        theEvent = [window nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)];
        click = [NSEvent mouseLocation];
        
        if (overClose) {
            BOOL newCloseState;
            
            click = [self convertPoint:[theEvent locationInWindow] fromView:nil];
            newCloseState = NSMouseInRect(click, closeRect, NO);
            if (newCloseState != clickingClose) {
                clickingClose = newCloseState;
                [self display];
            }
        } else if (!isDragging && !NSMouseInRect(click, hysterisisRect, NO)) {
            if ([theEvent clickCount] > 1) // don't drag on double-clicks
                break; 
            dragWindowHeight = [delegate headerViewDraggingHeight:self];
            isDragging = YES;
            clickingClose = NO;
            [delegate headerViewDidBeginDragging:self];     
            windowFrame.size.width = [window frame].size.width; // because width may change due to disconnection
            [self display];
        }
        
        if (isDragging) {
            NSPoint newPoint = NSMakePoint(click.x - windowOriginOffset.width, click.y - windowOriginOffset.height);
            NSRect resultRect;
            
            newTopLeft = NSMakePoint((CGFloat)round(newPoint.x), (CGFloat)round(newPoint.y + [window frame].size.height));
            
            NSScreen *screen = nil;
            for (NSScreen *testScreen in [NSScreen screens]) {
                if (NSPointInRect(click, [testScreen visibleFrame]))
                    screen = testScreen;
            }
            if (!screen)
                screen = [window screen];

            resultRect = [delegate headerView:self willDragWindowToFrame:NSMakeRect(newTopLeft.x, newTopLeft.y - dragWindowHeight, windowFrame.size.width, dragWindowHeight) onScreen:screen];
            
            // convert result group rect to result window rect
            resultRect.origin.y = NSMaxY(resultRect) - windowFrame.size.height;
            resultRect.size.height = windowFrame.size.height;
            
            [window setFrame:resultRect display:YES];
            newTopLeft = NSMakePoint(NSMinX(resultRect), NSMaxY(resultRect));
        }
    } while ([theEvent type] != NSLeftMouseUp);

    if (isDragging)
        [delegate headerViewDidEndDragging:self toFrame:NSMakeRect(newTopLeft.x, newTopLeft.y - dragWindowHeight, windowFrame.size.width, dragWindowHeight)];
    else if (clickingClose)
        [delegate headerViewDidClose:self];
    else if (!overClose && isInOriginalFrame && [self _allowToggleExpandedness])
        [delegate headerViewDidToggleExpandedness:self];
    isDragging = NO;
    isClicking = NO;
    overClose = NO;
    clickingClose = NO;
    [self display];
}


#pragma mark -
#pragma mark Private

- (BOOL)_allowToggleExpandedness;
{
    return ([OIInspectorGroup groupCount] > 1);
}

@end
