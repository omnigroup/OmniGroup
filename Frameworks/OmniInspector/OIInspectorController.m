// Copyright 2002-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIInspectorController.h"

#import <AppKit/AppKit.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

#import "OIInspector.h"
#import "OIInspectorGroup.h"
#import "OIInspectorHeaderView.h"
#import "OIInspectorHeaderBackground.h"
#import "OIInspectorRegistry.h"
#import "OIInspectorResizer.h"
#import "OIInspectorWindow.h"

#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/NSString-OAExtensions.h>

#include <sys/sysctl.h>

RCS_ID("$Id$");

@interface OIInspectorController (/*Private*/) <OIInspectorHeaderViewDelegateProtocol>
- (void)toggleVisibleAction:sender;
- (void)_buildHeadingView;
- (void)_buildWindow;
- (NSView *)_inspectorView;
- (void)_setExpandedness:(BOOL)expanded updateInspector:(BOOL)updateInspector withNewTopLeftPoint:(NSPoint)topLeftPoint animate:(BOOL)animate;
- (void)_saveInspectorHeight;
@end

NSComparisonResult sortByDefaultDisplayOrderInGroup(OIInspectorController *a, OIInspectorController *b, void *context)
{
    NSUInteger aOrder = [[a inspector] defaultOrderingWithinGroup];
    NSUInteger bOrder = [[b inspector] defaultOrderingWithinGroup];
    
    if (aOrder < bOrder)
        return NSOrderedAscending;
    else if (aOrder > bOrder)
        return NSOrderedDescending;
    else
        return NSOrderedSame;
}

@implementation OIInspectorController

// Init and dealloc

static BOOL animateInspectorToggles;

+ (void)initialize;
{
    NSNumber *number;
    
    OBINITIALIZE;
    
    number = [[NSUserDefaults standardUserDefaults] objectForKey:@"AnimateInspectorToggles"];
    if (number) {
        animateInspectorToggles = [number boolValue];
    } else {
        /* Take a guess as to whether we should animate. If we have multiple cores, we're on a fast-ish machine. */
        static const int hw_activecpu[] = { CTL_HW, HW_AVAILCPU };
        int ncpu;
        size_t bufsize = sizeof(ncpu);
        
        if(sysctl((int *)hw_activecpu, sizeof(hw_activecpu)/sizeof(hw_activecpu[0]), &ncpu, &bufsize, NULL, 0) == 0 &&
           bufsize == sizeof(ncpu)) {
            animateInspectorToggles = ( ncpu > 1 ) ? YES : NO;
        } else {
            perror("sysctl(hw.activecpu)");
            animateInspectorToggles = NO;
        }
    }
}

- initWithInspector:(OIInspector *)anInspector;
{
    if ([super init] == nil)
        return nil;

    inspector = [anInspector retain];
    isExpanded = NO;
    
    if ([inspector respondsToSelector:@selector(setInspectorController:)])
        [(id)inspector setInspectorController:self];
    
    return self;
}

// API

- (void)setGroup:(OIInspectorGroup *)aGroup;
{
    if (group != aGroup) {
        group = aGroup;
        if (group != nil)
            [headingButton setNeedsDisplay:YES];
    }
}

- (OIInspector *)inspector;
{
    return inspector;
}

- (NSWindow *)window;
{
    return window;
}

- (OIInspectorHeaderView *)headingButton;
{
    return headingButton;
}

- (BOOL)isExpanded;
{
    return isExpanded;
}

- (void)setExpanded:(BOOL)newState withNewTopLeftPoint:(NSPoint)topLeftPoint;
{
    [self _setExpandedness:newState updateInspector:YES withNewTopLeftPoint:topLeftPoint animate:NO];
}

- (NSString *)identifier;
{
    return [inspector identifier];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
    if ([item action] == @selector(toggleVisibleAction:)) {
        [item setState:isExpanded && [group isVisible]];
    }
    return YES;
}

- (CGFloat)headingHeight;
{
    return NSHeight([headingButton frame]);
}

- (CGFloat)desiredHeightWhenExpanded;
{
    OBPRECONDITION(headingButton); // That is, -loadInterface must have been called.
    CGFloat headingButtonHeight = headingButton ? NSHeight([headingButton frame]) : 0.0f;
    return NSHeight([[self _inspectorView] frame]) + headingButtonHeight;
}

- (void)toggleDisplay;
{
    if ([group isVisible]) {
        [self loadInterface]; // Load the UI and thus 'headingButton'
        [self headerViewDidToggleExpandedness:headingButton];
    } else {
        if (!isExpanded) {
            [self loadInterface]; // Load the UI and thus 'headingButton'
            [self headerViewDidToggleExpandedness:headingButton];
        }
        [group showGroup];
    }
}

- (void)updateTitle
{
    id newTitle;
    if ([inspector respondsToSelector:@selector(windowTitle)])
        newTitle = [(id)inspector windowTitle];
    else
        newTitle = [inspector displayName];
    [(id)headingButton setTitle:newTitle];
}

- (void)showInspector;
{
    if (![group isVisible] || !isExpanded)
        [self toggleDisplay];
    else
        [group orderFrontGroup]; 
}

- (BOOL)isVisible;
{
    return [group isVisible];
}

- (void)setBottommostInGroup:(BOOL)isBottom;
{
    if (isBottom == isBottommostInGroup)
        return;
    
    isBottommostInGroup = isBottom;
    if (window && !isExpanded) {
        NSRect windowFrame = [window frame];
        NSRect headingFrame;
        
        headingFrame.origin = NSMakePoint(0, isBottommostInGroup ? 0.0f : OIInspectorSpaceBetweenButtons);
        headingFrame.size = [headingButton frame].size;
        [window setFrame:NSMakeRect(NSMinX(windowFrame), NSMaxY(windowFrame) - NSMaxY(headingFrame), NSWidth(headingFrame), NSMaxY(headingFrame)) display:YES animate:NO];
    }
}

- (void)toggleExpandednessWithNewTopLeftPoint:(NSPoint)topLeftPoint animate:(BOOL)animate;
{
    [self _setExpandedness:!isExpanded updateInspector:YES withNewTopLeftPoint:topLeftPoint animate:animate];
}

- (void)updateExpandedness:(BOOL)allowAnimation; // call when the inspector sets its size internally by itself
{
    NSRect windowFrame = [window frame];
    [self _setExpandedness:isExpanded updateInspector:NO withNewTopLeftPoint:NSMakePoint(NSMinX(windowFrame), NSMaxY(windowFrame)) animate:allowAnimation&&animateInspectorToggles];
    if (isExpanded && resizerView != nil)
        [self queueSelectorOnce:@selector(_saveInspectorHeight)];
}

- (void)setNewPosition:(NSPoint)aPosition;
{
    newPosition = aPosition;
}

- (void)setCollapseOnTakeNewPosition:(BOOL)yn;
{
    collapseOnTakeNewPosition = yn;
}

- (CGFloat)heightAfterTakeNewPosition;  // Returns the frame height (not the content view height)
{
    if (collapseOnTakeNewPosition) {
        NSRect eventualContentRect = (NSRect){ { 0, 0 }, { OIInspectorStartingHeaderButtonWidth, OIInspectorStartingHeaderButtonHeight } };
        if (isBottommostInGroup)
            eventualContentRect.size.height += OIInspectorSpaceBetweenButtons;
        return [window frameRectForContentRect:eventualContentRect].size.height;
    } else
        return NSHeight([window frame]);
}

- (void)takeNewPositionWithWidth:(CGFloat)aWidth;  // aWidth is the frame width (not the content width)
{
    if (collapseOnTakeNewPosition) {
        [self toggleExpandednessWithNewTopLeftPoint:newPosition animate:NO];
    } else {
        NSRect frame = [window frame];
        
        frame.origin.x = newPosition.x;
        frame.origin.y = newPosition.y - frame.size.height;
        frame.size.width = aWidth;
        [window setFrame:frame display:YES];
    }
    collapseOnTakeNewPosition = NO;
}

- (void)loadInterface;
{
    if (!window)
        [self _buildWindow];
    needsToggleBeforeDisplay = ([[[OIInspectorRegistry sharedInspector] workspaceDefaults] objectForKey:[self identifier]] != nil) != isExpanded;
}

- (void)prepareWindowForDisplay;
{
    OBPRECONDITION(window);  // -loadInterface should have been called by this point.
    
    if (needsToggleBeforeDisplay && window) {
        NSRect windowFrame = [window frame];
        [self toggleExpandednessWithNewTopLeftPoint:NSMakePoint(NSMinX(windowFrame), NSMaxY(windowFrame)) animate:NO];
        needsToggleBeforeDisplay = NO;
    }
    [self updateInspector];
}

- (void)displayWindow;
{
    [window orderFront:self];
    [window resetCursorRects];
}

- (void)updateInspector;
{
    // See -[NSWindow(OAExtensions) replacement_setFrame:display:animate:], basically recursive animation calls on the same window can lead to crashes.  Using a non-zero delay here since I'm not sure what mode the AppKit timer is in (and it could be changed later).  So, if it happens to be in NSDefaultRunLoopMode (unlikely, but still possible), we'll only end up being called and delaying 20x/sec.
    if ([[window contentView] inLiveResize]) {
        [self performSelector:_cmd withObject:nil afterDelay:0.05 inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, nil]];
        return;
    }

    if (![group isVisible] || !isExpanded)
        return;

    NSArray *list = nil;
    NSResponder *oldResponder = nil;
    NS_DURING {
        
        // Don't update the inspector if the list of objects to inspect hasn't changed. -inspectedObjectsOfClass: returns a pointer-sorted list of objects, so we can just to 'identical' on the array.
        list = [[OIInspectorRegistry sharedInspector] copyObjectsInterestingToInspector:inspector];
        if ((!list && !currentlyInspectedObjects) || [list isIdenticalToArray:currentlyInspectedObjects]) {
            [list release];
            NS_VOIDRETURN;
        }
        
        // Record what was first responder in the inspector before we clear it.  We want to clear it since resigning first responder can cause controls to send actions and thus we want this happen *before* we change what would be affected by the action!
        oldResponder = [[[window firstResponder] retain] autorelease];
        if ([oldResponder isKindOfClass:[NSTextView class]] &&
            [[(NSTextView *)oldResponder delegate] isKindOfClass:[NSSearchField class]]) {
            oldResponder = nil;  // (Bug #32481)  don't make the window the first responder if user is typing in a search field because it ends editing
        } else {
            [window makeFirstResponder:window];
            
            // Since this is delayed, there is really no reasonable way for a NSResponder to refuse to resign here.  The selection has *already* changed!
            OBASSERT([window firstResponder] == window);
        }
        
        [currentlyInspectedObjects release];
	currentlyInspectedObjects = list; // takes ownership of the reference
        [inspector inspectObjects:currentlyInspectedObjects];
	list = nil;
    } NS_HANDLER {
        NSLog(@"-[%@ %@]: *** %@", [self class], NSStringFromSelector(_cmd), localException);
        [self inspectNothing];
    } NS_ENDHANDLER;

    // Restore the old first responder, unless it was a view that is no longer in the view hierarchy
    if ([oldResponder isKindOfClass:[NSView class]]) {
	NSView *view = (NSView *)oldResponder;
	if ([view window] != window)
	    oldResponder = nil;
    }
    if (oldResponder)
	[window makeFirstResponder:oldResponder];
    [list release];
}

- (void)inspectNothing;
{
    @try {
	[currentlyInspectedObjects release];
	currentlyInspectedObjects = nil;
        [inspector inspectObjects:nil];
    } @catch (NSException *exc) {
        OB_UNUSED_VALUE(exc);
    }
}

- (void)inspectorDidResize:(OIInspector *)resizedInspector;
{
    if (inspector != resizedInspector) {
        [inspector inspectorDidResize:resizedInspector];
    }
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *result = [super debugDictionary];
    
    
    [result setObject:[self identifier] forKey:@"identifier"];
    [result setObject:([window isVisible] ? @"YES" : @"NO") forKey:@"isVisible"];
    [result setObject:[window description] forKey:@"window"];
    if ([window childWindows])
        [result setObject:[[window childWindows] description] forKey:@"childWindows"];
    if ([window parentWindow])
        [result setObject:[[window parentWindow] description] forKey:@"parentWindow"];
    return result;
}

#pragma mark -
#pragma mark Private

- (void)toggleVisibleAction:sender;
{
    BOOL didExpand = NO;
    if (!isExpanded) {
        [self toggleDisplay];
        didExpand = YES;
    }
    if (![group isVisible]) {
        [group showGroup];
    } else if ([group isBelowOverlappingGroup]) {
        [group orderFrontGroup];
    } else if (!didExpand) {
        if ([group isOnlyExpandedMemberOfGroup:self])
            [group hideGroup];
        if ([[group inspectors] count] > 1) {
            [self loadInterface]; // Load the UI and thus 'headingButton'
            [self headerViewDidToggleExpandedness:headingButton];
        }
    }
}

- (void)_buildHeadingView;
{
    OBPRECONDITION(headingButton == nil);
    
    headingButton = [[OIInspectorHeaderView alloc] initWithFrame:NSMakeRect(0.0f, OIInspectorSpaceBetweenButtons,
                                                                            [[OIInspectorRegistry sharedInspector] inspectorWidth],
                                                                            OIInspectorStartingHeaderButtonHeight)];
    [headingButton setTitle:[inspector displayName]];

    NSImage *image = [inspector image];
    if (image)
	[headingButton setImage:image];

    NSString *keyEquivalent = [inspector shortcutKey];
    if ([keyEquivalent length]) {
        NSUInteger mask = [inspector shortcutModifierFlags];
        NSString *fullString = [NSString stringForKeyEquivalent:keyEquivalent andModifierMask:mask];
        [headingButton setKeyEquivalent:fullString];
    }
    [headingButton setDelegate:self];
    [headingButton setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
}

- (void)_buildWindow;
{
    [self _buildHeadingView];
    window = [[OIInspectorWindow alloc] initWithContentRect:NSMakeRect(500.0f, 300.0f, NSWidth([headingButton frame]), OIInspectorStartingHeaderButtonHeight + OIInspectorSpaceBetweenButtons) styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window setDelegate:self];
    [window setBecomesKeyOnlyIfNeeded:YES];
    [[window contentView] addSubview:headingButton];

    headingBackground = [[OIInspectorHeaderBackground alloc] initWithFrame:[headingButton frame]];
    [headingBackground setAutoresizingMask:[headingButton autoresizingMask]];
    [headingBackground setHeaderView:headingButton];
    [[window contentView] addSubview:headingBackground positioned:NSWindowBelow relativeTo:nil];
}

- (NSView *)_inspectorView;
{
    NSView *inspectorView = [inspector inspectorView];
    
    if (!loadedInspectorView) {
        forceResizeWidget = [inspector respondsToSelector:@selector(inspectorWillResizeToHeight:)]; 
        heightSizable = [inspectorView autoresizingMask] & NSViewHeightSizable ? YES : NO;

        if (forceResizeWidget) {
            _minimumHeight = 0;
        } else if ([inspector respondsToSelector:@selector(inspectorMinimumHeight)]) { 
            _minimumHeight = [inspector inspectorMinimumHeight];
        } else {
            _minimumHeight = [inspectorView frame].size.height;
        }
        
        NSString *savedHeightString = [[[OIInspectorRegistry sharedInspector] workspaceDefaults] objectForKey:[NSString stringWithFormat:@"%@-Height", [self identifier]]];

	NSSize size = [inspectorView frame].size;
	OBASSERT(size.width <= [[OIInspectorRegistry sharedInspector] inspectorWidth]); // OK to make inspectors wider, but probably indicates a problem if the nib is wider than the global inspector width
        if (size.width > [[OIInspectorRegistry sharedInspector] inspectorWidth]) {
            NSLog(@"Inspector %@ is wider (%g) than grouped width (%g)", [self identifier], size.width, [[OIInspectorRegistry sharedInspector] inspectorWidth]);
        }
	size.width = [[OIInspectorRegistry sharedInspector] inspectorWidth];
	
        if (savedHeightString != nil && heightSizable)
	    size.height = [savedHeightString floatValue];
	[inspectorView setFrameSize:size];
	
        loadedInspectorView = YES;
    }
    return inspectorView;
}

- (void)_setExpandedness:(BOOL)expanded updateInspector:(BOOL)updateInspector withNewTopLeftPoint:(NSPoint)topLeftPoint animate:(BOOL)animate;
{
    NSView *view = [self _inspectorView];
    BOOL hadVisibleInspectors = [[OIInspectorRegistry sharedInspector] hasVisibleInspector];

    if (!animateInspectorToggles)
        animate = NO;

    isExpanded = expanded;
    isSettingExpansion = YES;
    [group setScreenChangesEnabled:NO];
    [headingButton setExpanded:isExpanded];

    CGFloat additionalHeaderHeight;
    
    if (isExpanded) {

        if (updateInspector) {
            // If no inspectors were previously visible, the inspector registry's selection set may not be up-to-date, so tell it to update
            // (an alternate approach would be to have the registry keep track of whether or not it was up to date, and here we would simply tell the registry to update if it needed to, rather than us basing this off of whether or not any inspectors were previously visible, thus requiring us to know that -[OIInspectorRegistry _recalculateInspectorsAndInspectWindow] doesn't do anything if no inspectors are visible)
            if (!hadVisibleInspectors)
                [OIInspectorRegistry updateInspector];
            [self updateInspector]; // call this first because the view could change sizes based on the selection in -updateInspector
        }
            
        NSRect viewFrame = [view frame];
        NSRect newContentRect = NSMakeRect(0, 0,
                                           NSWidth(viewFrame),
                                           NSHeight([headingButton frame]) + NSHeight(viewFrame));
        NSRect windowFrame = [window frameRectForContentRect:newContentRect];
        windowFrame.origin.x = topLeftPoint.x;
        windowFrame.origin.y = topLeftPoint.y - windowFrame.size.height;
        windowFrame = [self windowWillResizeFromFrame:[window frame] toFrame:windowFrame];

        if (forceResizeWidget) {
            viewFrame = NSMakeRect(0, 0, NSWidth(newContentRect), NSHeight(viewFrame));
        } else {
            viewFrame.origin.x = (CGFloat)floor((NSWidth(newContentRect) - NSWidth(viewFrame)) / 2.0);
            viewFrame.origin.y = 0;
        }

        additionalHeaderHeight = [inspector additionalHeaderHeight];
        
        [view setFrame:viewFrame];
        [view setAutoresizingMask:NSViewNotSizable];
        [[window contentView] addSubview:view positioned:NSWindowBelow relativeTo:headingButton];
        [window setFrame:windowFrame display:YES animate:animate];
        if (forceResizeWidget || heightSizable) {
            if (!resizerView) {
                resizerView = [[OIInspectorResizer alloc] initWithFrame:NSMakeRect(0, 0, OIInspectorResizerWidth, OIInspectorResizerWidth)];
                [resizerView setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
            }
            [resizerView setFrameOrigin:NSMakePoint(NSMaxX(newContentRect) - OIInspectorResizerWidth, 0)];
            [[window contentView] addSubview:resizerView];
        }
        [view setAutoresizingMask:NSViewHeightSizable | NSViewMinXMargin | NSViewMaxXMargin];
        [[[OIInspectorRegistry sharedInspector] workspaceDefaults] setObject:@"YES" forKey:[self identifier]];
    } else {
	[window makeFirstResponder:window];

        [resizerView removeFromSuperview];
        [view setAutoresizingMask:NSViewNotSizable];
	
        NSRect headingFrame;
        headingFrame.origin = NSMakePoint(0, isBottommostInGroup ? 0.0f : OIInspectorSpaceBetweenButtons);
        if (group == nil)
            headingFrame.size = [headingButton frame].size;
        else
            headingFrame.size = NSMakeSize([[OIInspectorRegistry sharedInspector] inspectorWidth], [headingButton frame].size.height);
        NSRect headingWindowFrame = [window frameRectForContentRect:headingFrame];
        headingWindowFrame.origin.x = topLeftPoint.x;
        headingWindowFrame.origin.y = topLeftPoint.y - headingWindowFrame.size.height;
        [window setFrame:headingWindowFrame display:YES animate:animate];
        [view removeFromSuperview];

        additionalHeaderHeight = 0;
        
        if (updateInspector)
            [self inspectNothing];
        
        [[[OIInspectorRegistry sharedInspector] workspaceDefaults] removeObjectForKey:[self identifier]];
    }
    
    NSRect headingFrame;
    if (additionalHeaderHeight > 0) {
        headingFrame = [headingButton frame];
        headingFrame.size.height += additionalHeaderHeight;
        headingFrame.origin.y -= additionalHeaderHeight;
    } else
        headingFrame = [headingButton frame];
    if (!NSEqualRects(headingFrame, [headingBackground frame])) {
        [headingBackground setFrame:headingFrame];
        [headingBackground setNeedsDisplay:YES];
    }
    
    [[OIInspectorRegistry sharedInspector] defaultsDidChange];
    [group setScreenChangesEnabled:YES];
    isSettingExpansion = NO;
}

- (void)_saveInspectorHeight;
{
    OIInspectorRegistry *registry = [OIInspectorRegistry sharedInspector];
    NSSize size = [[self _inspectorView] frame].size;

    [[registry workspaceDefaults] setObject:[NSNumber numberWithCGFloat:size.height] forKey:[NSString stringWithFormat:@"%@-Height", [self identifier]]];
    [registry defaultsDidChange];
}

#pragma mark NSWindow delegate

- (void)windowWillClose:(NSNotification *)notification;
{
    [self inspectNothing];
}

- (void)windowDidBecomeKey:(NSNotification *)notification;
{
    [headingBackground setNeedsDisplay:YES];
}

- (void)windowDidResignKey:(NSNotification *)notification;
{
    [headingBackground setNeedsDisplay:YES];
    [window makeFirstResponder:window];
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)aWindow;
{
    NSWindow *mainWindow;
    NSResponder *nextResponder;
    NSUndoManager *undoManager = nil;
    
    mainWindow = [NSApp mainWindow];
    nextResponder = [mainWindow firstResponder];
    if (nextResponder == nil)
        nextResponder = mainWindow;
    
    do {
        if ([nextResponder respondsToSelector:@selector(undoManager)])
            undoManager = [nextResponder undoManager];
        else if ([nextResponder respondsToSelector:@selector(delegate)] && [[(id)nextResponder delegate] respondsToSelector:@selector(undoManager)])
            undoManager = [[(id)nextResponder delegate] undoManager];
        nextResponder = [nextResponder nextResponder];
    } while (nextResponder && !undoManager);
    
    return undoManager;
}

#pragma mark OIInspectorWindow delegate

- (void)windowWillBeginResizing:(NSWindow *)resizingWindow;
{
    OBASSERT(resizingWindow == window);
    [group inspectorWillStartResizing:self];
}

- (void)windowDidFinishResizing:(NSWindow *)resizingWindow;
{
    OBASSERT(resizingWindow == window);
    [group inspectorDidFinishResizing:self];
}

/*"
 If you call this method, you must also call -windowDidFinishResizing: after the resize is actually complete. The reason is that this method calls a corresponding method on the inspector group which sets up some resizing stuff that must be cleaned up when the resizing is complete.
 Good news, everybody! OIInspectorWindow automatically calls -windowDidFinishResizing: at the end of -setFrame:display:animate:, so if that's the method you use to perform the actual resize, you don't need to call -windowDidFinishResizing: yourself.
"*/
- (NSRect)windowWillResizeFromFrame:(NSRect)fromRect toFrame:(NSRect)toRect;
{
    NSRect result;

    if ([group ignoreResizing]) {
        return toRect;
    }

    NSRect newContentRect = [window contentRectForFrameRect:toRect];
    
    if (isExpanded && !isSettingExpansion) {
        if ([inspector respondsToSelector:@selector(inspectorMinimumHeight)])
            _minimumHeight = [inspector inspectorMinimumHeight];

        if (NSHeight(newContentRect) < _minimumHeight)
            newContentRect.size.height = _minimumHeight;
    }
    if (isExpanded && forceResizeWidget) {
        newContentRect.size.height -= OIInspectorStartingHeaderButtonHeight;
        newContentRect.size.height = [inspector inspectorWillResizeToHeight:newContentRect.size.height];
        newContentRect.size.height += OIInspectorStartingHeaderButtonHeight;
    }

    newContentRect.size.width = [[OIInspectorRegistry sharedInspector] inspectorWidth];
    
    toRect = [window frameRectForContentRect:newContentRect];
    
    if (isExpanded && !isSettingExpansion && !forceResizeWidget && !heightSizable) {
        toRect.origin.y += NSHeight(fromRect) - NSHeight(toRect);
        toRect.size.height = NSHeight(fromRect);
    }
    
    if (group != nil) {
        result = [group inspector:self willResizeToFrame:toRect isSettingExpansion:isSettingExpansion];
	OBASSERT(result.size.width == toRect.size.width); // Not allowed to width-size inspectors ever!
    } else
        result = toRect;
    
    if (isExpanded && !isSettingExpansion && resizerView != nil)
        [self queueSelectorOnce:@selector(_saveInspectorHeight)];
    return result;
}

#pragma mark OIInspectorHeaderViewDelegateProtocol

- (BOOL)headerViewShouldDisplayCloseButton:(OIInspectorHeaderView *)view;
{
    return [group isHeadOfGroup:self];
}

- (CGFloat)headerViewDraggingHeight:(OIInspectorHeaderView *)view;
{
    NSRect myGroupFrame;
    
    if (!window || ![group getGroupFrame:&myGroupFrame]) {
        OBASSERT_NOT_REACHED("Can't calculate headerViewDraggingHeight");
        return 1.0f;
    }
    
    return NSMaxY([window frame]) - myGroupFrame.origin.y;
}

- (void)headerViewDidBeginDragging:(OIInspectorHeaderView *)view;
{
    [group detachFromGroup:self];
}

- (NSRect)headerView:(OIInspectorHeaderView *)view willDragWindowToFrame:(NSRect)aFrame onScreen:(NSScreen *)screen;
{
    aFrame = [group fitFrame:aFrame onScreen:screen forceVisible:NO];
    aFrame = [group snapToOtherGroupWithFrame:aFrame];
    return aFrame;
}

- (void)headerViewDidEndDragging:(OIInspectorHeaderView *)view toFrame:(NSRect)aFrame;
{
    [group windowsDidMoveToFrame:aFrame];
}

- (void)headerViewDidToggleExpandedness:(OIInspectorHeaderView *)senderButton;
{
    OBPRECONDITION(senderButton);
    
    if ([group canBeginResizingOperation]) {
        NSRect windowFrame = [window frame];
        [self toggleExpandednessWithNewTopLeftPoint:NSMakePoint(NSMinX(windowFrame), NSMaxY(windowFrame)) animate:YES];
    } else {
        // try again when the current resizing operation may be done
        [self performSelector:@selector(headerViewDidToggleExpandedness:) withObject:senderButton afterDelay:0.1];
    }
}

- (void)headerViewDidClose:(OIInspectorHeaderView *)view;
{
    [group hideGroup];
}

@end
