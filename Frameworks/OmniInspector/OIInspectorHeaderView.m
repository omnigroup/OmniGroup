// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIInspectorHeaderView.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/OAAquaButton.h>
#import <OmniAppKit/NSAttributedString-OAExtensions.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniInspector/OIInspectorGroup.h>
#import <OmniInspector/OIInspectorRegistry.h>

RCS_ID("$Id$")


@implementation OIInspectorHeaderView
{
    BOOL isClicking, isDragging, clickingClose, overClose;
}

@synthesize delegate = _weak_delegate;

typedef enum {
    OIInspectorHeaderImageHeightNormal, OIInspectorHeaderImageHeightTall, OIInspectorHeaderImageHeightCount,
} OIInspectorHeaderImageHeight;
static NSString *OIInspectorHeaderImageHeightNames[OIInspectorHeaderImageHeightCount] = {@"", @"Tall"};

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

static NSImage *_headerImages[OIInspectorHeaderImageHeightCount][OIInspectorKeyStatusCount][OIInspectorHeaderImageStateCount];

static NSImage *_expandedImage, *_collapsedImage;

static NSImage *_closeButtonImages[OIInspectorHeaderImageTintCount][OIInspectorCloseButtonStateCount];

static NSDictionary *_textAttributes, *_keyEquivalentAttributes;

static BOOL omitTextAndStateWhenCollapsed;

static NSGradient *unifiedGradientKey, *unifiedGradientNonKey;

+ (void)initialize;
{
    OBINITIALIZE;

    {
        OIInspectorHeaderImageHeight heightIndex;
        for (heightIndex = 0; heightIndex < OIInspectorHeaderImageHeightCount; heightIndex++) {
            OIInspectorKeyStatus keyStatusIndex;
            for (keyStatusIndex = 0; keyStatusIndex < OIInspectorKeyStatusCount; keyStatusIndex++) {
                OIInspectorHeaderImageState stateIndex;
                for (stateIndex = 0; stateIndex < OIInspectorHeaderImageStateCount; stateIndex++) {
                    NSString *imageName = [NSString stringWithFormat:@"OI%@Titlebar%@%@", OIInspectorHeaderImageHeightNames[heightIndex], OIInspectorHeaderImageKeyStatusNames[keyStatusIndex], OIInspectorHeaderImageStateNames[stateIndex]];
                    _headerImages[heightIndex][keyStatusIndex][stateIndex] = OAImageNamed(imageName, [OIInspectorHeaderView bundle]);
                    OBASSERT(_headerImages[heightIndex][keyStatusIndex][stateIndex]);
                }
            }
        }
    }

    {
        OIInspectorHeaderImageTint tintIndex;
        for (tintIndex = 0; tintIndex < OIInspectorHeaderImageTintCount; tintIndex++) {
            OIInspectorCloseButtonState stateIndex;
            for (stateIndex = 0; stateIndex < OIInspectorCloseButtonStateCount; stateIndex++) {
                NSString *imageName = [NSString stringWithFormat:@"OIWindowSmallCloseBox%@%@", OIInspectorCloseButtonStateNames[stateIndex], OIInspectorHeaderImageTintNames[tintIndex]];
                _closeButtonImages[tintIndex][stateIndex] = OAImageNamed(imageName, [OIInspectorHeaderView bundle]);
		OBASSERT(_closeButtonImages[tintIndex][stateIndex]);
            }
        }
    }

    _expandedImage = OAImageNamed(@"OIExpanded", [OIInspectorHeaderView bundle]);
    OBASSERT(_expandedImage);
    _collapsedImage = OAImageNamed(@"OICollapsed", [OIInspectorHeaderView bundle]);
    OBASSERT(_collapsedImage);

    _textAttributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:[NSFont labelFontSize]], NSFontAttributeName, nil];
    _keyEquivalentAttributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:[NSFont labelFontSize]], NSFontAttributeName, [NSColor darkGrayColor], NSForegroundColorAttributeName, nil];

    omitTextAndStateWhenCollapsed = [[NSUserDefaults standardUserDefaults] boolForKey:@"OmitTextAndStateWhenCollapsed"];
    
    unifiedGradientKey = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:0.77f alpha:1.0f] endingColor:[NSColor colorWithWhite:.59f alpha:1.0f]];
    unifiedGradientNonKey = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:0.84f alpha:1.0f] endingColor:[NSColor colorWithWhite:.72f alpha:1.0f]];
    
}

- (void)setTitle:(NSString *)aTitle;
{
    if (OFISEQUAL(_title, aTitle))
        return;
    _title = [aTitle copy];
    [self setNeedsDisplay:YES];
}

#define IMAGE_SIZE (13.0f)

- (void)setImage:(NSImage *)anImage;
{
    if (_image == anImage)
        return;

    // If the image is PDF, we don't want to uses it's native size (which might be too big).
    [anImage setSize:NSMakeSize(IMAGE_SIZE, IMAGE_SIZE)];
    _image = anImage;
    [self setNeedsDisplay:YES];
}

- (void)setKeyEquivalent:(NSString *)anEquivalent;
{
    if (OFISEQUAL(_keyEquivalent, anEquivalent))
        return;
    [self setNeedsDisplay:YES];
}

- (void)setExpanded:(BOOL)newState;
{
    if (_expanded == newState)
        return;
    _expanded = newState;
    [self setNeedsDisplay:YES];
}

- (void)setDelegate:(NSObject <OIInspectorHeaderViewDelegateProtocol> *)aDelegate;
{
    _weak_delegate = aDelegate;
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
    NSObject <OIInspectorHeaderViewDelegateProtocol> *delegate = _weak_delegate;
    
    if ([delegate headerViewShouldDisplayCloseButton:self]) {
        NSRect bounds = [self titleContentBounds];
        CGFloat yAdjustment = NSHeight(bounds) - OIInspectorStartingHeaderButtonHeight;
        NSRect closeRect = NSMakeRect(NSMinX(bounds) + 6.0f, NSMinY(bounds) + 1.0f + yAdjustment, 14.0f, 14.0f);
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

- (CGRect)titleContentBounds;
{
    NSRect bounds = self.bounds;

    if (self.accessoryView) {
        bounds.size = CGSizeMake(NSWidth(bounds), self.titleContentHeight);
    }

    return bounds;
}

- (void)drawBackgroundImageForBounds:(NSRect)backgroundBounds inRect:(NSRect)dirtyRect;
{
    OIInspectorKeyStatus keyStatus = (OIInspectorKeyStatus)[[self window] isKeyWindow];
    
    NSRect gradient = backgroundBounds;
    gradient.origin.y += 1;
    gradient.size.height -= 2;
    
    NSGradient *blend = keyStatus? unifiedGradientKey : unifiedGradientNonKey;
    [blend drawInRect:gradient angle:90];
    
    [[NSColor colorWithWhite:(keyStatus) ? 0.86f : 0.91f alpha:1.0f] set];
    NSRectFill(NSMakeRect(0,0, backgroundBounds.size.width, 1));
    [[NSColor colorWithWhite:(keyStatus) ? .25f : .53f  alpha:1.0f] set];
    NSRectFill(NSMakeRect(0,backgroundBounds.size.height-1, backgroundBounds.size.width, 1));
}

- (void)drawRect:(NSRect)aRect;
{
    NSObject <OIInspectorHeaderViewDelegateProtocol> *delegate = _weak_delegate;

    BOOL drawAll = _expanded || !omitTextAndStateWhenCollapsed;
    OIInspectorHeaderImageTint imageTint = ([NSColor currentControlTint] == NSBlueControlTint) ? OIInspectorHeaderImageTintBlue : OIInspectorHeaderImageTintGraphite;
    
    NSRect bounds = [self titleContentBounds];
    CGFloat nextElementX = NSMinX(bounds) + 6.0f;
    if ([delegate headerViewShouldDisplayCloseButton:self]) {
        NSImage *closeImage = _closeButtonImages[imageTint][clickingClose ? OIInspectorCloseButtonStatePressed : (overClose ? OIInspectorCloseButtonStateRollover : OIInspectorCloseButtonStateNormal)];
        NSRect closeImagePoint = NSMakeRect(nextElementX, NSMinY(bounds) + 1.0f, closeImage.size.width, closeImage.size.height);
        
        [closeImage drawFlippedInRect:closeImagePoint operation:NSCompositingOperationSourceOver];
    }
    nextElementX += 20.0f;
    
    if (drawAll && [self _allowToggleExpandedness]) {
        NSImage *disclosureImage = _expanded ? _expandedImage : _collapsedImage;
        NSRect disclosureImageRect = NSMakeRect(nextElementX, rint(NSMidY(bounds) - [disclosureImage size].height / 2.0f) - 1, disclosureImage.size.width, disclosureImage.size.height);

        [disclosureImage drawFlippedInRect:disclosureImageRect operation:NSCompositingOperationSourceOver];

        if (isClicking && !overClose && !isDragging) // our triangle images are 100% black, but about 50% opaque, so we just draw it again over itself
            [disclosureImage drawFlippedInRect:disclosureImageRect operation:NSCompositingOperationSourceOver fraction:0.6666f];

        nextElementX += 20.0f;
    }
    
    if (_image != nil) {
        NSGraphicsContext *currentContext = [NSGraphicsContext currentContext];
        CGContextRef cgContext = [currentContext CGContext];

        CGContextSaveGState(cgContext);
        CGContextTranslateCTM(cgContext, nextElementX, NSMaxY(bounds)-2.0f);
        CGContextScaleCTM(cgContext, 1.0f, -1.0f);
        [_image drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0f];
        CGContextRestoreGState(cgContext);
    }
    
    CGFloat keyEquivalentWidth;
    if ([NSString isEmptyString:_keyEquivalent])
        keyEquivalentWidth = 0.0f;
    else
        keyEquivalentWidth = [_keyEquivalent sizeWithAttributes:_keyEquivalentAttributes].width + 5.0f;
    
    if (drawAll) {
        NSRect windowRect = self.window.frame;
        NSRect rect = NSMakeRect(NSMinX(bounds), NSMinY(bounds), NSWidth(windowRect), NSHeight(bounds));
        if ([_title isKindOfClass:[NSAttributedString class]]) {
            [(NSAttributedString *)_title drawInRectangle:rect alignment:NSTextAlignmentCenter verticallyCentered:YES];
        } else {
            NSAttributedString *attr = [[NSAttributedString alloc] initWithString:_title attributes:_textAttributes];
            [attr drawInRectangle:rect alignment:NSTextAlignmentCenter verticallyCentered:YES];
        }
    }

    [_keyEquivalent drawAtPoint:NSMakePoint(NSMaxX(bounds) - keyEquivalentWidth, NSMinY(bounds) + 1.0f) withAttributes:_keyEquivalentAttributes];
}

- (CGFloat)heightNeededWhenExpanded;
{
    CGFloat height = self.titleContentHeight;
    if (self.accessoryView) {
        height += NSHeight(self.accessoryView.frame);
    }
    return height;
}

- (void)setAccessoryView:(NSView *)accessoryView;
{
    _accessoryView = accessoryView;
    [self addSubview:accessoryView];
}

- (void)mouseDown:(NSEvent *)theEvent;
{
    NSPoint click = [NSEvent mouseLocation];
    NSWindow *window = [self window];
    NSRect windowFrame = [window frame];
    NSSize windowOriginOffset = NSMakeSize(click.x - windowFrame.origin.x, click.y - windowFrame.origin.y);
    NSRect hysterisisRect = NSMakeRect(click.x - 3.0f, click.y - 3.0f, 6.0f, 6.0f);
    NSRect bounds = self.bounds;
    NSRect closeRect = NSMakeRect(NSMinX(bounds) + 6.0f, NSMaxY(bounds)-1.0f - (14.0f + NSHeight(self.accessoryView.frame)), 14.0f, 14.0f);
    NSPoint newTopLeft = NSMakePoint(NSMinX(windowFrame), NSMaxY(windowFrame));
    CGFloat dragWindowHeight = 0.0f;
    BOOL isInOriginalFrame = NSPointInRect([self convertPoint:[theEvent locationInWindow] fromView:nil], [self bounds]);  // don't collapse if the mousedown is not within the header frame (as when this is called from tab area)
    
    click = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    
    NSObject <OIInspectorHeaderViewDelegateProtocol> *delegate = _weak_delegate;

    isDragging = NO;
    isClicking = YES;
    overClose = clickingClose = [delegate headerViewShouldDisplayCloseButton:self] && NSMouseInRect(click, closeRect, NO);
    [self display];
    
    do {
        theEvent = [window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        click = [NSEvent mouseLocation];
        
        if (overClose) {
            BOOL newCloseState;
            
            click = [self convertPoint:[theEvent locationInWindow] fromView:nil];
            newCloseState = NSMouseInRect(click, closeRect, NO);
            if (newCloseState != clickingClose) {
                clickingClose = newCloseState;
                [self display];
            }
        } else if (!isDragging && !NSMouseInRect(click, hysterisisRect, NO) && [delegate headerViewShouldAllowDragging:self]) {
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
    } while ([theEvent type] != NSEventTypeLeftMouseUp);

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

#pragma mark - Private

- (BOOL)_allowToggleExpandedness;
{
    NSObject <OIInspectorHeaderViewDelegateProtocol> *delegate = _weak_delegate;

    if ([delegate respondsToSelector:@selector(headerViewShouldDisplayExpandButton:)])
        return [delegate headerViewShouldDisplayExpandButton:self];
    
    return ![[OIInspectorRegistry inspectorRegistryForMainWindow] hasSingleInspector];
}

@end
