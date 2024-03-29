// Copyright 1997-2021 Omni Development, Inc. All rights reserved.
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

#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/NSView-OAExtensions.h>
#import <OmniAppKit/OAApplication.h>
#import <OmniAppKit/OAPageSelectableDocumentProtocol.h>
#import <OmniAppKit/OAZoomableViewProtocol.h>

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

    smallSystemFont = [NSFont systemFontOfSize:10.0f];
}

- initWithFrame:(NSRect)theFrame;
{
    if (!(self = [super initWithFrame:theFrame]))
        return nil;
    
    [self _setupScrollView];
    // Default scroller settings for OAScrollViews
    [self setHasHorizontalScroller:YES];
    [self setHasVerticalScroller:YES];
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    [self _setupScrollView];
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [self removeFromSuperview];
    [horizontalWidgetsBox removeFromSuperview];
    [pageUpButton removeFromSuperview];
    [pageDownButton removeFromSuperview];
    [scalePopUpButton removeFromSuperview];
    [pagePromptTextField removeFromSuperview];
    [pageNumberTextField removeFromSuperview];
    [pagesCountTextField removeFromSuperview];
}

- (NSSize)contentSizeForFrameSize:(NSSize)frameSize hasHorizontalScroller:(BOOL)hasHorizontalScroller hasVerticalScroller:(BOOL)hasVerticalScroller;
{
    NSSize contentSize;
    CGFloat scrollerWidthDifference;

    Class horizontalScrollerClass = hasHorizontalScroller ? [NSScroller class] : Nil;
    Class verticleScrollerClass = hasVerticalScroller ? [NSScroller class] : Nil;
    
    contentSize = [[self class] contentSizeForFrameSize:frameSize horizontalScrollerClass:horizontalScrollerClass verticalScrollerClass:verticleScrollerClass borderType:[self borderType] controlSize:NSControlSizeRegular scrollerStyle:[NSScroller preferredScrollerStyle]];

    if (hasVerticalScroller) {
        NSScroller *verticalScroller = self.verticalScroller;
        NSScrollerStyle scrollerStyle = [[verticalScroller class] preferredScrollerStyle];
        scrollerWidthDifference = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:scrollerStyle] - [NSScroller scrollerWidthForControlSize:[verticalScroller controlSize] scrollerStyle:scrollerStyle];
        contentSize.width += scrollerWidthDifference;
    }

    if (hasHorizontalScroller) {
        NSScroller *horizontalScroller = self.horizontalScroller;
        NSScrollerStyle scrollerStyle = [[horizontalScroller class] preferredScrollerStyle];
        scrollerWidthDifference = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:scrollerStyle] - [NSScroller scrollerWidthForControlSize:[horizontalScroller controlSize] scrollerStyle:scrollerStyle];
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

- (void)zoomToScale:(CGFloat)newZoomFactor;
{
    if (newZoomFactor == zoomFactor)
        return;

    zoomFactor = newZoomFactor;
    [[self documentView] zoomTo:newZoomFactor];
    [[self documentView] displayIfNeeded];
}

- (void)zoomFromSender:(NSMenuItem *)sender;
{
    NSInteger tag;

    // This hack is needed under 4.2.  Maybe Rhapsody is better.
    if ([sender isKindOfClass:[NSMatrix class]]) {
        OBASSERT_NOT_REACHED("Should get the menu, not the internal NSMatrix (if there even is one still)");
        tag = [[(NSMatrix *)sender selectedCell] tag];
    } else {
        tag = [sender tag];
    }

    CGFloat newZoomFactor = (CGFloat)(tag / 100.0);
    [self zoomToScale:newZoomFactor];
}

- (CGFloat)zoomFactor;
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
	[pagePromptTextField setAlignment:NSTextAlignmentRight];
	[pagePromptTextField setBackgroundColor:[NSColor controlColor]];
        [pagePromptTextField setBezeled:NO];
	[pagePromptTextField setEditable:NO];
	[pagePromptTextField setSelectable:NO];
	[horizontalWidgetsBox addSubview:pagePromptTextField];
	
        pageNumberTextField = [[NSTextField alloc] initWithFrame:textRect];
	[pageNumberTextField setFont:smallSystemFont];
	[pageNumberTextField setAlignment:NSTextAlignmentCenter];
        [pageNumberTextField setBezeled:NO];
        [pageNumberTextField setBordered:YES];
	[pageNumberTextField setTarget:self];
	[pageNumberTextField setAction:@selector(gotoPage:)];
        OBASSERT( ! [nonretained_delegate isKindOfClass:[NSViewController class]], "Delegate of class %@ is a subclass on NSViewController. As such it will be inserted into the responder chain twice, likely creating an infinite regress as it becomes its own next responder.", [nonretained_delegate class]);
	[pageNumberTextField setNextResponder:nonretained_delegate];
        [pageNumberTextField setRefusesFirstResponder:YES];
	[horizontalWidgetsBox addSubview:pageNumberTextField];

        pagesCountTextField = [[NSTextField alloc] initWithFrame:textRect];
	[pagesCountTextField setFont:smallSystemFont];
	[pagesCountTextField setAlignment:NSTextAlignmentLeft];
        [pagesCountTextField setBackgroundColor:[NSColor controlColor]];
	[pagesCountTextField setBezeled:NO];
	[pagesCountTextField setEditable:NO];
	[pagesCountTextField setSelectable:NO];
	[horizontalWidgetsBox addSubview:pagesCountTextField];
    } else {
	[pagePromptTextField removeFromSuperview];
	pagePromptTextField = nil;
	[pageNumberTextField removeFromSuperview];
	pageNumberTextField = nil;
	[pagesCountTextField removeFromSuperview];
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

- (BOOL)processKeyDownCharacter:(unichar)character modifierFlags:(NSUInteger)modifierFlags;
{
    enum {
        UnicharDeleteKey  = 0x007F,
        UnicharNonBreakingSpaceKey  = 0x00A0
    };

    [NSCursor setHiddenUntilMouseMoves:YES];
    switch (character) {
        case NSUpArrowFunctionKey:
            if (modifierFlags & NSEventModifierFlagOption)
                [self scrollDownByPages:-1.0f];
            else
                [self scrollDownByLines:-3.0f];
            return YES;
        case NSDownArrowFunctionKey:
            if (modifierFlags & NSEventModifierFlagOption)
                [self scrollDownByPages:1.0f];
            else
                [self scrollDownByLines:3.0f];
            return YES;
        case NSLeftArrowFunctionKey:
            if (modifierFlags & NSEventModifierFlagOption)
                [self scrollRightByPages:-1.0f];
            else
                [self scrollRightByLines:-3.0f];
            return YES;
        case NSRightArrowFunctionKey:
            if (modifierFlags & NSEventModifierFlagOption)
                [self scrollRightByPages:1.0f];
            else
                [self scrollRightByLines:3.0f];
            return YES;
        case NSPageUpFunctionKey:
            [self scrollDownByPages:-1.0f];
            return YES;
        case NSPageDownFunctionKey:
            [self scrollDownByPages:1.0f];
            return YES;
        case NSHomeFunctionKey:
            if (modifierFlags & NSEventModifierFlagShift)
                [self scrollToEnd];
            else
                [self scrollToTop];
            return YES;
        case NSEndFunctionKey:
            [self scrollToEnd];
            return YES;
        case UnicharDeleteKey:
        case UnicharNonBreakingSpaceKey: // Alt-Space
            [self scrollDownByPages:-1.0f];
            return YES;
        case ' ':
            if (modifierFlags & NSEventModifierFlagShift)
                [self scrollDownByPages:-1.0f];
            else
                [self scrollDownByPages:1.0f];
            return YES;
        case 'u':
            [self scrollDownByPages:-0.5f];
            return YES;
        case 'd':
            [self scrollDownByPages:0.5f];
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

        verticalWidget = newVerticalWidget;

        [self tile];
    }
}
        
- (NSView *)verticalWidget
{
    return verticalWidget;
}

- (void)setControlSize:(NSControlSize)newControlSize;
{
    NSControlSize oldControlSize;
    CGFloat scrollerWidthDifference, contentWidth, contentHeight, documentWidth, documentHeight;

    contentWidth = NSWidth([[self contentView] frame]);
    contentHeight = NSHeight([[self contentView] frame]);
    documentWidth = NSWidth([[self documentView] frame]);
    documentHeight = NSHeight([[self documentView] frame]);
        
    if ([self hasVerticalScroller]) {
        NSScroller *verticalScroller = [self verticalScroller];
        NSScrollerStyle scrollerStyle = [[verticalScroller class] preferredScrollerStyle];
        
        oldControlSize = [verticalScroller controlSize];
        [verticalScroller setControlSize:newControlSize];
        scrollerWidthDifference = [NSScroller scrollerWidthForControlSize:oldControlSize scrollerStyle:scrollerStyle] - [NSScroller scrollerWidthForControlSize:newControlSize scrollerStyle:scrollerStyle];
        contentWidth += scrollerWidthDifference;
        documentWidth += scrollerWidthDifference;
    }
    if ([self hasHorizontalScroller]) {
        NSScroller *horizontalScroller = [self horizontalScroller];
        NSScrollerStyle scrollerStyle = [[horizontalScroller class] preferredScrollerStyle];
        oldControlSize = [horizontalScroller controlSize];
        [horizontalScroller setControlSize:newControlSize];
        scrollerWidthDifference = [NSScroller scrollerWidthForControlSize:oldControlSize scrollerStyle:scrollerStyle] - [NSScroller scrollerWidthForControlSize:newControlSize scrollerStyle:scrollerStyle];
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

	zoomFactor = 1.0f;
	[scalePopUpButton selectItemWithTitle:OBUnlocalized(@"100%")];
        [scalePopUpButton setRefusesFirstResponder:YES];
	[horizontalWidgetsBox addSubview:scalePopUpButton];
    } else {
	[scalePopUpButton removeFromSuperview];
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
            NSDivideRect(widgetsAreaRect, &widgetRect, &widgetsAreaRect, 80.0f, NSMinXEdge);
            widgetRect = NSInsetRect(widgetRect, 1.0f, -1.0f);
            [scalePopUpButton setFrame:widgetRect];
        }

        if (pagePromptTextField && hasMultiplePages) {
            NSDivideRect(widgetsAreaRect, &widgetRect, &widgetsAreaRect, 39, NSMinXEdge);
            widgetRect = NSInsetRect(widgetRect, 1.0f, 0.0f);
            widgetRect.origin.y -= 1.0f;
            [pagePromptTextField setFrame:widgetRect];

            NSDivideRect(widgetsAreaRect, &widgetRect, &widgetsAreaRect, 37, NSMinXEdge);
            widgetRect = NSInsetRect(widgetRect, 1.0f, 0.0f);
            widgetRect.origin.y -= 1.0f;
            widgetRect.size.height += 2.0f;
            [pageNumberTextField setFrame:widgetRect];

            NSDivideRect(widgetsAreaRect, &widgetRect, &widgetsAreaRect, 40, NSMinXEdge);
            widgetRect = NSInsetRect(widgetRect, 1.0f, 0.0f);
            widgetRect.origin.y -= 1.0f;
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

        widgetSize = NSMakeSize(16.0f, 16.0f);

        scrollerRect = [[self verticalScroller] frame];
        adjustedScroller = NO;

        // Lay out the page up and page down buttons
        if(hasMultiplePages) {
            if (pageDownButton) {
                // lop off the size we want, plus a pixel for spacing below
                NSDivideRect(scrollerRect, &widgetRect, &scrollerRect, widgetSize.height + 1.0f, NSMaxYEdge);
                widgetRect.size = widgetSize;
                widgetRect = NSOffsetRect(widgetRect, 1.0f, 0.0f);
                if (![pageDownButton superview])
                    [self addSubview:pageDownButton];
                [pageDownButton setFrame:widgetRect];
                adjustedScroller = YES;
            }

            if (pageUpButton) {
                NSDivideRect(scrollerRect, &widgetRect, &scrollerRect, widgetSize.height + 1.0f, NSMaxYEdge);
                widgetRect.size = widgetSize;
                widgetRect = NSOffsetRect(widgetRect, 1.0f, 0.0f);
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
        theEvent = [[NSApplication sharedApplication] nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantPast] inMode:NSEventTrackingRunLoopMode dequeue:NO];
        // Break the loop if there is no next event
        if (!theEvent)
            break;
        // Skip over key-up events
        else if ([theEvent type] == NSEventTypeKeyUp) {
            [super keyUp:[[NSApplication sharedApplication] nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantPast] inMode:NSEventTrackingRunLoopMode dequeue:YES]];
            continue;
        }
        // Respond only to key-down events
        else if ([theEvent type] == NSEventTypeKeyDown) {
            [self processKeyDownEvent:[[NSApplication sharedApplication] nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantPast] inMode:NSEventTrackingRunLoopMode dequeue:YES]];
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
    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
    CGFloat border;

    switch ([self borderType]) {
        default:
        case NSNoBorder:
            border = 0.0f;
            if (drawsBackground) {
                [[NSColor controlColor] set];
                NSRectFill(rect);
            }
            break;
        case NSBezelBorder:
            border = 2.0f;
            NSDrawDarkBezel([self bounds], rect);
            break;
        case NSLineBorder:
            border = 1.0f;
            if (drawsBackground) {
                [[NSColor controlColor] set];
                NSRectFill(rect);
            }
            [[NSColor separatorColor] set];
            NSFrameRect([self bounds]);
            break;
        case NSGrooveBorder:
            border = 2.0f;
            NSDrawGroove([self bounds], rect);
            break;
    }

    [super drawRect:rect];

    BOOL somethingToDraw = NO;

    if ([self hasHorizontalScroller]) {
	NSRect aRect = [[self horizontalScroller] frame];
	if (!NSIsEmptyRect(NSIntersectionRect(aRect, rect))) {
	    somethingToDraw = YES;
	    CGContextMoveToPoint(context, NSMinX(aRect) + border, NSMinY(aRect) - 1.0f);
	    CGContextAddLineToPoint(context, NSMaxX(aRect) - 2.0f * border, NSMinY(aRect) - 1.0f);
	}
    }
    if ([self hasVerticalScroller]) {
	NSRect aRect = [[self verticalScroller] frame];
	if (!NSIsEmptyRect(NSIntersectionRect(aRect, rect))) {
	    somethingToDraw = YES;

            // Scrollers are on the right
            CGContextMoveToPoint(context, NSMinX(aRect) - 1.0f, NSMinY(aRect) + border);
            CGContextAddLineToPoint(context, NSMinX(aRect) - 1.0f, NSMaxY(aRect) - 2.0f * border);
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
    BOOL processedAtLeastOneCharacter = NO;

    [NSCursor setHiddenUntilMouseMoves:YES];
    NSString *characters = [keyDownEvent characters];
    NSUInteger modifierFlags = [keyDownEvent modifierFlags];
    NSUInteger characterCount = [characters length];
    for (NSUInteger characterIndex = 0; characterIndex < characterCount; characterIndex++) {
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
        [self scrollDownByPages:-1.0f];
}

- (void)pageDown:(id)sender;
{
    if (flags.delegateIsPageSelectable)
        [nonretained_delegate pageDown];
    else
        [self scrollDownByPages:1.0f];
}

- (void)zoomIn:(id)sender;
{
    unsigned int zoomIndex;

    if (!scalePopUpButton)
        return;

    for (zoomIndex = 0; startingScales[zoomIndex] > 0; zoomIndex++) {
        if (zoomFactor * 100.0f < startingScales[zoomIndex]) {
            [scalePopUpButton selectItemWithTitle:[NSString stringWithFormat:@"%d%%", startingScales[zoomIndex]]];
            [self zoomToScale:startingScales[zoomIndex] / 100.0f];
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
        if (zoomFactor * 100.0f <= startingScales[zoomIndex]) {
            [scalePopUpButton selectItemWithTitle:[NSString stringWithFormat:@"%d%%", startingScales[zoomIndex - 1]]];
            [self zoomToScale:startingScales[zoomIndex - 1] / 100.0f];
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
