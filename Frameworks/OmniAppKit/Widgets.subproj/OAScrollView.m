// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAScrollView.h>

#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "NSImage-OAExtensions.h"
#import "NSView-OAExtensions.h"
#import "OAApplication.h"
#import "OAPageSelectableDocumentProtocol.h"
#import "OAZoomableViewProtocol.h"

RCS_ID("$Id$")

@interface OAScrollView (Private)
- (void)_setupScrollView;
- (void)processKeyDownEvent:(NSEvent *)keyDownEvent;
- (void)pageUp:(id)sender;
- (void)pageDown:(id)sender;
- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
- (void)addOrRemoveScrollersIfNeeded;
- (void)autoScrollTile;
@end

@implementation OAScrollView

static int startingScales[] = {50, 75, 100, 125, 150, 200, 400, 0};
static NSFont *smallSystemFont;

+ (void)initialize;
{
    OBINITIALIZE;

    smallSystemFont = [NSFont systemFontOfSize:10.0];
}

- initWithFrame:(NSRect)theFrame;
{
    if ([super initWithFrame:theFrame] == nil)
        return nil;
    
    [self _setupScrollView];
    // Default scroller settings for OAScrollViews
    [self setHasHorizontalScroller:YES];
    [self setHasVerticalScroller:YES];
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    if ([super initWithCoder:coder] == nil)
        return nil;
    [self _setupScrollView];
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [self removeFromSuperview];
    [horizontalWidgetsBox removeFromSuperview];
    [horizontalWidgetsBox release];
    [pageUpButton removeFromSuperview];
    [pageUpButton release];
    [pageDownButton removeFromSuperview];
    [pageDownButton release];
    [scalePopUpButton removeFromSuperview];
    [scalePopUpButton release];
    [pagePromptTextField removeFromSuperview];
    [pagePromptTextField release];
    [pageNumberTextField removeFromSuperview];
    [pageNumberTextField release];
    [pagesCountTextField removeFromSuperview];
    [pagesCountTextField release];

    [super dealloc];
}

- (NSSize)contentSizeForFrameSize:(NSSize)frameSize hasHorizontalScroller:(BOOL)hasHorizontalScroller hasVerticalScroller:(BOOL)hasVerticalScroller;
{
    NSSize contentSize;
    float scrollerWidthDifference;

    contentSize = [isa contentSizeForFrameSize:frameSize hasHorizontalScroller:hasHorizontalScroller hasVerticalScroller:hasVerticalScroller borderType:[self borderType]];

    if (hasVerticalScroller) {
        scrollerWidthDifference = [NSScroller scrollerWidthForControlSize:NSRegularControlSize] - [NSScroller scrollerWidthForControlSize:[[self verticalScroller] controlSize]];
        contentSize.width += scrollerWidthDifference;
    }

    if (hasHorizontalScroller) {
        scrollerWidthDifference = [NSScroller scrollerWidthForControlSize:NSRegularControlSize] - [NSScroller scrollerWidthForControlSize:[[self horizontalScroller] controlSize]];
        contentSize.height += scrollerWidthDifference;
    }

    return contentSize;
}

- (NSSize)contentSizeForFrameSize:(NSSize)fSize;
{
    return [self contentSizeForFrameSize:fSize hasHorizontalScroller:[self hasHorizontalScroller] hasVerticalScroller:[self hasVerticalScroller]];
}

- (NSSize)contentSizeForHorizontalScroller:(BOOL)hasHorizontalScroller verticalScroller:(BOOL)hasVerticalScroller;
{
    return [self contentSizeForFrameSize:[self frame].size hasHorizontalScroller:hasHorizontalScroller hasVerticalScroller:hasVerticalScroller];
}

- (void)zoomToScale:(double)newZoomFactor;
{
    if (newZoomFactor == zoomFactor)
        return;

    zoomFactor = newZoomFactor;
    [[self documentView] zoomTo:newZoomFactor];
    [[self documentView] displayIfNeeded];
}

- (void)zoomFromSender:(NSMenuItem *)sender;
{
    double newZoomFactor;

    // This hack is needed under 4.2.  Maybe Rhapsody is better.
    if ([sender isKindOfClass:[NSMatrix class]])
        sender = [(NSMatrix *)sender selectedCell];

    newZoomFactor = [sender tag] / 100.0;
    [self zoomToScale:newZoomFactor];
}

- (float)zoomFactor;
{
    return zoomFactor;
}

- (void)setDelegate:(id)newDelegate;
{
    nonretained_delegate = newDelegate;

    flags.delegateIsPageSelectable = (nonretained_delegate != nil && [nonretained_delegate conformsToProtocol:@protocol(OAPageSelectableDocument)])? 1 : 0;

    if (flags.delegateIsPageSelectable) {
	NSRect                      textRect;

	textRect = [[self horizontalScroller] frame];

        pagePromptTextField = [[NSTextField alloc] initWithFrame:textRect];
	[pagePromptTextField setFont:smallSystemFont];
	[pagePromptTextField setStringValue:NSLocalizedStringFromTableInBundle(@"Page", @"OmniAppKit", [OAScrollView bundle], "page prompt for multipage documents in scrollview")];
	[pagePromptTextField setAlignment:NSRightTextAlignment];
	[pagePromptTextField setBackgroundColor:[NSColor controlColor]];
        [pagePromptTextField setBezeled:NO];
	[pagePromptTextField setEditable:NO];
	[pagePromptTextField setSelectable:NO];
	[horizontalWidgetsBox addSubview:pagePromptTextField];
	
        pageNumberTextField = [[NSTextField alloc] initWithFrame:textRect];
	[pageNumberTextField setFont:smallSystemFont];
	[pageNumberTextField setAlignment:NSCenterTextAlignment];
        [pageNumberTextField setBezeled:NO];
        [pageNumberTextField setBordered:YES];
	[pageNumberTextField setTarget:self];
	[pageNumberTextField setAction:@selector(gotoPage:)];
	[pageNumberTextField setNextResponder:nonretained_delegate];
        [pageNumberTextField setRefusesFirstResponder:YES];
	[horizontalWidgetsBox addSubview:pageNumberTextField];

        pagesCountTextField = [[NSTextField alloc] initWithFrame:textRect];
	[pagesCountTextField setFont:smallSystemFont];
	[pagesCountTextField setAlignment:NSLeftTextAlignment];
        [pagesCountTextField setBackgroundColor:[NSColor controlColor]];
	[pagesCountTextField setBezeled:NO];
	[pagesCountTextField setEditable:NO];
	[pagesCountTextField setSelectable:NO];
	[horizontalWidgetsBox addSubview:pagesCountTextField];
    } else {
	[pagePromptTextField removeFromSuperview];
	[pagePromptTextField release];
	pagePromptTextField = nil;
	[pageNumberTextField removeFromSuperview];
	[pageNumberTextField release];
	pageNumberTextField = nil;
	[pagesCountTextField removeFromSuperview];
	[pagesCountTextField release];
	pagesCountTextField = nil;
    }

    [self tile];
}

- (ScrollingBehavior)scrollBehavior;
{
    return scrollBehavior;
}

- (void)setScrollBehavior:(ScrollingBehavior)behavior;
{
    scrollBehavior = behavior;
    switch (scrollBehavior) {
        case YES_SCROLL:
            [self setHasHorizontalScroller:YES];
            [self setHasVerticalScroller:YES];
            break;
        case NO_SCROLL:
            [self setHasHorizontalScroller:NO];
            [self setHasVerticalScroller:NO];
            break;
        case AUTO_SCROLL:
        case VERTICAL_SCROLL:
            // Scrollers will be dynamically adjusted as needed
            break;
        case MANUAL_SCROLL:
            // Someone else will control the scrollers
            break;
    }
}

- (void)showingPageNumber:(int)pageNumber of:(unsigned int)pagesCount;
{
    if (pageNumber < 0)
        [pageNumberTextField setStringValue:@""];
    else
        [pageNumberTextField setIntValue:pageNumber + 1];
    [pagesCountTextField setStringValue:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"of %d", @"OmniAppKit", [OAScrollView bundle], "how many pages in document format for scrollview"), pagesCount]];
    [pageNumberTextField setNextResponder:[self documentView]];
}

- (void)gotoPage:(id)sender;
{
    [nonretained_delegate displayPageNumber:[sender intValue] - 1];
    [pageNumberTextField setNextResponder:[self documentView]];
}

- (BOOL)processKeyDownCharacter:(unichar)character modifierFlags:(unsigned int)modifierFlags;
{
    enum {
        UnicharDeleteKey  = 0x007F,
        UnicharNonBreakingSpaceKey  = 0x00A0
    };

    [NSCursor setHiddenUntilMouseMoves:YES];
    switch (character) {
        case NSUpArrowFunctionKey:
            if (modifierFlags & NSAlternateKeyMask)
                [self scrollDownByPages:-1.0];
            else
                [self scrollDownByLines:-3.0];
            return YES;
        case NSDownArrowFunctionKey:
            if (modifierFlags & NSAlternateKeyMask)
                [self scrollDownByPages:1.0];
            else
                [self scrollDownByLines:3.0];
            return YES;
        case NSLeftArrowFunctionKey:
            if (modifierFlags & NSAlternateKeyMask)
                [self scrollRightByPages:-1.0];
            else
                [self scrollRightByLines:-3.0];
            return YES;
        case NSRightArrowFunctionKey:
            if (modifierFlags & NSAlternateKeyMask)
                [self scrollRightByPages:1.0];
            else
                [self scrollRightByLines:3.0];
            return YES;
        case NSPageUpFunctionKey:
            [self scrollDownByPages:-1.0];
            return YES;
        case NSPageDownFunctionKey:
            [self scrollDownByPages:1.0];
            return YES;
        case NSHomeFunctionKey:
            if (modifierFlags & NSShiftKeyMask)
                [self scrollToEnd];
            else
                [self scrollToTop];
            return YES;
        case NSEndFunctionKey:
            [self scrollToEnd];
            return YES;
        case UnicharDeleteKey:
        case UnicharNonBreakingSpaceKey: // Alt-Space
            [self scrollDownByPages:-1.0];
            return YES;
        case ' ':
            if (modifierFlags & NSShiftKeyMask)
                [self scrollDownByPages:-1.0];
            else
                [self scrollDownByPages:1.0];
            return YES;
        case 'u':
            [self scrollDownByPages:-0.5];
            return YES;
        case 'd':
            [self scrollDownByPages:0.5];
            return YES;
        case 'f':
            [self pageDown:nil];
            return YES;
        case 'b':
            [self pageUp:nil];
            return YES;
        case '[':
            [self zoomIn:nil];
            return YES;
        case ']':
            [self zoomOut:nil];
            return YES;
        default:
            return NO;
    }
}

//

- (void)setSmoothScrollEnabled:(BOOL)smoothScrollEnabled;
{
    flags.smoothScrollDisabled = !smoothScrollEnabled;
}

- (BOOL)smoothScrollEnabled;
{
    return !flags.smoothScrollDisabled;
}

- (void)setVerticalWidget:(NSView *)newVerticalWidget
{
    if (newVerticalWidget != verticalWidget) {
        if (verticalWidget)
            [verticalWidget removeFromSuperview];

        [newVerticalWidget retain];
        [verticalWidget release];
        verticalWidget = newVerticalWidget;

        [self tile];
    }
}
        
- (NSView *)verticalWidget
{
    return verticalWidget;
}


- (NSSize)idealSizeForAvailableSize:(NSSize)availableSize;
{
    NSClipView *clipView;
    NSView *docView;
    NSSize docViewSize;
    NSSize scrollViewSize;
    BOOL hasHorizontalScroller, hasVerticalScroller;

    clipView = [self contentView];
    docView = [clipView documentView];
    if (docView == nil)
        docViewSize = NSZeroSize;
    else if ([docView respondsToSelector:@selector(idealSizeForAvailableSize:)])
        docViewSize = [(id)docView idealSizeForAvailableSize:[self contentSizeForFrameSize:availableSize hasHorizontalScroller:(scrollBehavior == YES_SCROLL) hasVerticalScroller:(scrollBehavior == YES_SCROLL)]];
    else
        docViewSize = [docView frame].size;

    switch (scrollBehavior) {
        case YES_SCROLL:
            hasHorizontalScroller = YES;
            hasVerticalScroller = YES;
            break;
        case NO_SCROLL:
            hasHorizontalScroller = NO;
            hasVerticalScroller = NO;
            break;
        case VERTICAL_SCROLL:
            scrollViewSize = [isa frameSizeForContentSize:docViewSize hasHorizontalScroller:NO hasVerticalScroller:NO borderType:[self borderType]];
            hasVerticalScroller = scrollViewSize.height > availableSize.height;
            hasHorizontalScroller = NO;
            break;
        default:
        case AUTO_SCROLL:
            scrollViewSize = [isa frameSizeForContentSize:docViewSize hasHorizontalScroller:NO hasVerticalScroller:NO borderType:[self borderType]];
            hasVerticalScroller = scrollViewSize.height > availableSize.height;
            scrollViewSize = [isa frameSizeForContentSize:docViewSize hasHorizontalScroller:NO hasVerticalScroller:hasVerticalScroller borderType:[self borderType]];
            hasHorizontalScroller = scrollViewSize.width > availableSize.width;
            break;
        case MANUAL_SCROLL:
            hasHorizontalScroller = [self hasHorizontalScroller];
            hasVerticalScroller = [self hasVerticalScroller];
            break;
    }
    scrollViewSize = [isa frameSizeForContentSize:docViewSize hasHorizontalScroller:hasHorizontalScroller hasVerticalScroller:hasVerticalScroller borderType:[self borderType]];
    return scrollViewSize;
}

- (void)setControlSize:(NSControlSize)newControlSize;
{
    NSControlSize oldControlSize;
    float scrollerWidthDifference, contentWidth, contentHeight, documentWidth, documentHeight;

    contentWidth = NSWidth([[self contentView] frame]);
    contentHeight = NSHeight([[self contentView] frame]);
    documentWidth = NSWidth([[self documentView] frame]);
    documentHeight = NSHeight([[self documentView] frame]);
        
    if ([self hasVerticalScroller]) {
        oldControlSize = [[self verticalScroller] controlSize];
        [[self verticalScroller] setControlSize:newControlSize];
        scrollerWidthDifference = [NSScroller scrollerWidthForControlSize:oldControlSize] - [NSScroller scrollerWidthForControlSize:newControlSize];
        contentWidth += scrollerWidthDifference;
        documentWidth += scrollerWidthDifference;
    }
    if ([self hasHorizontalScroller]) {
        oldControlSize = [[self horizontalScroller] controlSize];
        [[self horizontalScroller] setControlSize:newControlSize];
        scrollerWidthDifference = [NSScroller scrollerWidthForControlSize:oldControlSize] - [NSScroller scrollerWidthForControlSize:newControlSize];
        contentHeight += scrollerWidthDifference;
        documentHeight += scrollerWidthDifference;
    }
    
    [[self contentView] setFrameSize:NSMakeSize(contentWidth, contentHeight)];
    [[self documentView] setFrameSize:NSMakeSize(documentWidth, documentHeight)];
}

// NSScrollView subclass

- (void)setDocumentView:(NSView *)aView
{
    if ([aView conformsToProtocol:@protocol(OAZoomableView)]) {
	unsigned int scaleIndex;

	/* create scale scalePopUpButton */
	scalePopUpButton = [[NSPopUpButton alloc] init];
        [scalePopUpButton setBordered:NO];
        [scalePopUpButton setFont:[NSFont systemFontOfSize:10]];
	for (scaleIndex = 0; startingScales[scaleIndex] != 0; scaleIndex++) {
	    NSString *title = [NSString stringWithFormat:@"%d%%", startingScales[scaleIndex]];
	    [scalePopUpButton addItemWithTitle:title];
            NSMenuItem *scaleCell = [scalePopUpButton itemWithTitle:title];
	    [scaleCell setTag:startingScales[scaleIndex]];
	    [scaleCell setTarget:self];
	    [scaleCell setAction:@selector(zoomFromSender:)];
	}

	zoomFactor = 1.0;
	[scalePopUpButton selectItemWithTitle:@"100%"];
        [scalePopUpButton setRefusesFirstResponder:YES];
	[horizontalWidgetsBox addSubview:scalePopUpButton];
    } else {
	[scalePopUpButton removeFromSuperview];
	[scalePopUpButton release];
	scalePopUpButton = nil;
    }

    [super setDocumentView:aView];
    [self addOrRemoveScrollersIfNeeded];
}

- (void)tile;
{
    BOOL hasMultiplePages, showHorizontalWidgets;
    NSClipView *clipView;
    NSView *docView;

    if (flags.tiling)
        return;
    flags.tiling = YES;

    clipView = [self contentView];
    docView = [clipView documentView];

    if (scrollBehavior == AUTO_SCROLL || scrollBehavior == VERTICAL_SCROLL)
        [self autoScrollTile];
    else
        [super tile];

    hasMultiplePages = NSHeight([docView frame]) > [self contentSize].height || flags.delegateIsPageSelectable;

    // Set up widgets in horizontal scroller
    if (![self hasHorizontalScroller]) {
        showHorizontalWidgets = NO;
    } else {
        NSRect scrollerRect, widgetRect;
        NSRect widgetsAreaRect, widgetsBoxRect;

        scrollerRect = [[self horizontalScroller] frame];
        widgetsBoxRect = scrollerRect;
        widgetsAreaRect = NSMakeRect(0, 0, scrollerRect.size.width, scrollerRect.size.height);

        if (scalePopUpButton) {
            NSDivideRect(widgetsAreaRect, &widgetRect, &widgetsAreaRect, 80.0, NSMinXEdge);
            widgetRect = NSInsetRect(widgetRect, 1.0, -1.0);
            [scalePopUpButton setFrame:widgetRect];
        }

        if (pagePromptTextField && hasMultiplePages) {
            NSDivideRect(widgetsAreaRect, &widgetRect, &widgetsAreaRect, 39, NSMinXEdge);
            widgetRect = NSInsetRect(widgetRect, 1.0, 0.0);
            widgetRect.origin.y -= 1.0;
            [pagePromptTextField setFrame:widgetRect];

            NSDivideRect(widgetsAreaRect, &widgetRect, &widgetsAreaRect, 37, NSMinXEdge);
            widgetRect = NSInsetRect(widgetRect, 1.0, 0.0);
            widgetRect.origin.y -= 1.0;
            widgetRect.size.height += 2.0;
            [pageNumberTextField setFrame:widgetRect];

            NSDivideRect(widgetsAreaRect, &widgetRect, &widgetsAreaRect, 40, NSMinXEdge);
            widgetRect = NSInsetRect(widgetRect, 1.0, 0.0);
            widgetRect.origin.y -= 1.0;
            [pagesCountTextField setFrame:widgetRect];
        }

        scrollerRect.size.width -= NSMinX(widgetsAreaRect);
        [[self horizontalScroller] setFrame:scrollerRect];

        widgetsBoxRect.size.width = NSMinX(widgetsAreaRect);
        widgetsBoxRect.origin.x = NSMaxX(scrollerRect);
        [horizontalWidgetsBox setFrame:widgetsBoxRect];

        showHorizontalWidgets = ( widgetsBoxRect.size.width > 0 ) && [[horizontalWidgetsBox subviews] count] > 0;
    }

    if (showHorizontalWidgets && ![horizontalWidgetsBox superview])
        [self addSubview:horizontalWidgetsBox];
    if (!showHorizontalWidgets && [horizontalWidgetsBox superview])
        [horizontalWidgetsBox removeFromSuperview];

    // Set up widgets in vertical scroller
    if (![self hasVerticalScroller]) {
        // No vertical scroller, therefore no widgets in the vertical scroller space.
        [pageDownButton removeFromSuperview];
        [pageUpButton removeFromSuperview];
        [verticalWidget removeFromSuperview];
    } else {
        NSRect scrollerRect, widgetRect;
        NSSize widgetSize;
        BOOL adjustedScroller;

        widgetSize = NSMakeSize(16.0, 16.0);

        scrollerRect = [[self verticalScroller] frame];
        adjustedScroller = NO;

        // Lay out the page up and page down buttons
        if(hasMultiplePages) {
            if (pageDownButton) {
                // lop off the size we want, plus a pixel for spacing below
                NSDivideRect(scrollerRect, &widgetRect, &scrollerRect, widgetSize.height + 1.0, NSMaxYEdge);
                widgetRect.size = widgetSize;
                widgetRect = NSOffsetRect(widgetRect, 1.0, 0.0);
                if (![pageDownButton superview])
                    [self addSubview:pageDownButton];
                [pageDownButton setFrame:widgetRect];
                adjustedScroller = YES;
            }

            if (pageUpButton) {
                NSDivideRect(scrollerRect, &widgetRect, &scrollerRect, widgetSize.height + 1.0, NSMaxYEdge);
                widgetRect.size = widgetSize;
                widgetRect = NSOffsetRect(widgetRect, 1.0, 0.0);
                if (![pageUpButton superview])
                    [self addSubview:pageUpButton];
                [pageUpButton setFrame:widgetRect];
                adjustedScroller = YES;
            }
        } else {
            if ([pageUpButton superview])
                [pageUpButton removeFromSuperview];
            if ([pageDownButton superview])
                [pageDownButton removeFromSuperview];
        }
        
        // Lay out the user-supplied vertical widget
        if (verticalWidget != nil) {
            widgetSize = [verticalWidget frame].size;
            NSDivideRect(scrollerRect, &widgetRect, &scrollerRect, widgetSize.height, NSMinYEdge);
            widgetRect.size.height = widgetSize.height;
            if (![verticalWidget superview])
                [self addSubview:verticalWidget];
            [verticalWidget setFrame:widgetRect];
            adjustedScroller = YES;
        }

        if (adjustedScroller)
            [[self verticalScroller] setFrame:scrollerRect];
    }

    [self setNeedsDisplay:YES];
    flags.tiling = NO;
}

- (void)reflectScrolledClipView:(NSClipView *)aClipView;
{
    [super reflectScrolledClipView:aClipView];
    [self addOrRemoveScrollersIfNeeded];
}

// NSResponder subclass

- (BOOL)acceptsFirstResponder;
{
    return YES;
}

- (void)keyDown:(NSEvent *)theEvent;
{
    if (pageNumberTextField) {
        NSString *characters;

        characters = [theEvent characters];
        if ([characters length] > 0) {
            unichar keyDownCharacter;

            keyDownCharacter = [[theEvent characters] characterAtIndex:0];
            if (keyDownCharacter >= '0' && keyDownCharacter <= '9') {
                [pageNumberTextField selectText:nil];
                [[[self window] firstResponder] keyDown:theEvent];
                return;
            }
        }
    }

    [self processKeyDownEvent:theEvent];

    while (YES) {
        // Peek at the next event
        theEvent = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantPast] inMode:NSEventTrackingRunLoopMode dequeue:NO];
        // Break the loop if there is no next event
        if (!theEvent)
            break;
        // Skip over key-up events
        else if ([theEvent type] == NSKeyUp) {
            [super keyUp:[NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantPast] inMode:NSEventTrackingRunLoopMode dequeue:YES]];
            continue;
        }
        // Respond only to key-down events
        else if ([theEvent type] == NSKeyDown) {
            [self processKeyDownEvent:[NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantPast] inMode:NSEventTrackingRunLoopMode dequeue:YES]];
        }
        // Break the loop on all other event types
        else
            break;
    }

    [self displayIfNeeded];
    // TODO: Need to collapse keyboard input events here
    // Used to call:
    // PSWait();
}

// NSView subclass

- (void)drawRect:(NSRect)rect;
{
    BOOL drawsBackground = [self drawsBackground];
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    float border;

    switch ([self borderType]) {
        default:
        case NSNoBorder:
            border = 0.0;
            if (drawsBackground) {
                [[NSColor controlColor] set];
                NSRectFill(rect);
            }
            break;
        case NSBezelBorder:
            border = 2.0;
            NSDrawDarkBezel([self bounds], rect);
            break;
        case NSLineBorder:
            border = 1.0;
            if (drawsBackground) {
                [[NSColor controlColor] set];
                NSRectFill(rect);
            }
            [[NSColor controlDarkShadowColor] set];
            NSFrameRect([self bounds]);
            break;
        case NSGrooveBorder:
            border = 2.0;
            NSDrawGroove([self bounds], rect);
            break;
    }

    [super drawRect:rect];

    BOOL somethingToDraw = NO;

    if ([self hasHorizontalScroller]) {
	NSRect aRect = [[self horizontalScroller] frame];
	if (!NSIsEmptyRect(NSIntersectionRect(aRect, rect))) {
	    somethingToDraw = YES;
	    CGContextMoveToPoint(context, NSMinX(aRect) + border, NSMinY(aRect) - 1.0);
	    CGContextAddLineToPoint(context, NSMaxX(aRect) - 2.0 * border, NSMinY(aRect) - 1.0);
	}
    }
    if ([self hasVerticalScroller]) {
	NSRect aRect = [[self verticalScroller] frame];
	if (!NSIsEmptyRect(NSIntersectionRect(aRect, rect))) {
	    somethingToDraw = YES;

            // Scrollers are on the right
            CGContextMoveToPoint(context, NSMinX(aRect) - 1.0, NSMinY(aRect) + border);
            CGContextAddLineToPoint(context, NSMinX(aRect) - 1.0, NSMaxY(aRect) - 2.0 * border);
        }
    }

    if (somethingToDraw) {
        [[NSColor controlDarkShadowColor] set];
        CGContextStrokePath(context);
    }
}

@end

@implementation OAScrollView (Private)

- (void)_setupScrollView;
{
    scrollBehavior = AUTO_SCROLL;
    horizontalWidgetsBox = [[NSView alloc] initWithFrame:NSZeroRect];
    [[self contentView] setAutoresizesSubviews:YES];
    [self addSubview:horizontalWidgetsBox];
}

- (void)processKeyDownEvent:(NSEvent *)keyDownEvent;
{
    NSString *characters;
    unsigned int modifierFlags;
    unsigned int characterIndex, characterCount;
    BOOL processedAtLeastOneCharacter = NO;

    [NSCursor setHiddenUntilMouseMoves:YES];
    characters = [keyDownEvent characters];
    modifierFlags = [keyDownEvent modifierFlags];
    characterCount = [characters length];
    for (characterIndex = 0; characterIndex < characterCount; characterIndex++) {
        if ([self processKeyDownCharacter:[characters characterAtIndex:characterIndex] modifierFlags:modifierFlags])
            processedAtLeastOneCharacter = YES;
    }
    if (!processedAtLeastOneCharacter)
        [super keyDown:keyDownEvent];
}

- (void)pageUp:(id)sender;
{
    if (flags.delegateIsPageSelectable)
        [nonretained_delegate pageUp];
    else
        [self scrollDownByPages:-1.0];
}

- (void)pageDown:(id)sender;
{
    if (flags.delegateIsPageSelectable)
        [nonretained_delegate pageDown];
    else
        [self scrollDownByPages:1.0];
}

- (void)zoomIn:(id)sender;
{
    unsigned int zoomIndex;

    if (!scalePopUpButton)
        return;

    for (zoomIndex = 0; startingScales[zoomIndex] > 0; zoomIndex++) {
        if (zoomFactor * 100.0 < startingScales[zoomIndex]) {
            [scalePopUpButton selectItemWithTitle:[NSString stringWithFormat:@"%d%%", startingScales[zoomIndex]]];
            [self zoomToScale:startingScales[zoomIndex] / 100.0];
            break;
        }
    }
}

- (void)zoomOut:(id)sender;
{
    unsigned int zoomIndex;

    if (!scalePopUpButton)
        return;

    for (zoomIndex = 1; startingScales[zoomIndex] > 0; zoomIndex++) {
        if (zoomFactor * 100.0 <= startingScales[zoomIndex]) {
            [scalePopUpButton selectItemWithTitle:[NSString stringWithFormat:@"%d%%", startingScales[zoomIndex - 1]]];
            [self zoomToScale:startingScales[zoomIndex - 1] / 100.0];
            break;
        }
    }
}

- (void)addOrRemoveScrollersIfNeeded;
{
    if (scrollBehavior == AUTO_SCROLL || scrollBehavior == VERTICAL_SCROLL) {
        NSRect docViewFrame;
        NSSize potentialContentSize;
        BOOL needsVerticalScroller, needsHorizontalScroller;

        docViewFrame = [[self documentView] frame];
        potentialContentSize = [self contentSizeForHorizontalScroller:NO verticalScroller:YES];
        needsVerticalScroller = NSHeight(docViewFrame) > potentialContentSize.height;
        if (!needsVerticalScroller) {
            potentialContentSize = [self contentSizeForHorizontalScroller:NO verticalScroller:NO];
        }
        needsHorizontalScroller = (NSWidth(docViewFrame) > potentialContentSize.width) && scrollBehavior != VERTICAL_SCROLL;
        if ([self hasVerticalScroller] != needsVerticalScroller ||
            [self hasHorizontalScroller] != needsHorizontalScroller) {
            [self tile];
            [self setNeedsDisplayInRect:[self bounds]];
        }
    }
}

- (void)autoScrollTile;
{
    NSClipView *clipView = [self contentView];
    NSView *docView = [clipView documentView];
    BOOL notifyDocView = [docView respondsToSelector:@selector(scrollViewDidChangeScrollers)];

    if (!docView) {
        if ([self hasVerticalScroller])
            [self setHasVerticalScroller:NO];
        if ([self hasHorizontalScroller])
            [self setHasHorizontalScroller:NO];
        [super tile];
        return;
    }
    
    [super tile];

    BOOL needsVerticalScroller = NSHeight([docView frame]) > [self contentSizeForHorizontalScroller:NO verticalScroller:YES].height;
    if (needsVerticalScroller != [self hasVerticalScroller]) {
#if 0
        NSLog(@"%@ needsVerticalScroller? %.1f > %.1f = %d", OBShortObjectDescription(self), NSHeight([docView frame]), [self contentSizeForHorizontalScroller:NO verticalScroller:YES].height, needsVerticalScroller);
#endif
        [self setHasVerticalScroller:needsVerticalScroller];
        [super tile];
        if (notifyDocView)
            [docView scrollViewDidChangeScrollers];
    }

    BOOL needsHorizontalScroller = (NSWidth([docView frame]) > [self contentSize].width) && scrollBehavior != VERTICAL_SCROLL;
    if (needsHorizontalScroller != [self hasHorizontalScroller]) {
#if 0
        NSLog(@"%@ needsHorizontalScroller? %.1f > %.1f = %d", OBShortObjectDescription(self), NSWidth([docView frame]), [self contentSize].width, needsHorizontalScroller);
#endif
        [self setHasHorizontalScroller:needsHorizontalScroller];
        [super tile];
    }
}

@end
