// Copyright 2002-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIInspectorController.h>

#import <AppKit/AppKit.h>
#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/NSString-OAExtensions.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniInspector/OIInspector.h>
#import <OmniInspector/OIInspectorGroup.h>
#import <OmniInspector/OIInspectorHeaderView.h>
#import <OmniInspector/OIInspectorRegistry.h>
#import <OmniInspector/OIInspectorWindow.h>
#import <OmniInspector/OIWorkspace.h>
#include <sys/sysctl.h>

#import "OIInspectorController-Internal.h"
#import "OIInspectorHeaderBackground.h"


RCS_ID("$Id$");

NSString * const OIInspectorControllerDidChangeExpandednessNotification = @"OIInspectorControllerDidChangeExpandedness";

@interface OIInspectorController () <OIInspectorHeaderViewDelegateProtocol>

@property (nonatomic, strong) NSView *embeddedContainerView;

@end

NSComparisonResult OISortByDefaultDisplayOrderInGroup(OIInspectorController *a, OIInspectorController *b)
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
{
    NSArray *currentlyInspectedObjects;
    NSString *currentInspectionIdentifier;
    OIInspector <OIConcreteInspector> *inspector;
    OIInspectorWindow *window;
    OIInspectorHeaderView *headingButton;
    OIInspectorHeaderBackground *headingBackground;
    NSView *controlsView;
    BOOL loadedInspectorView, isBottommostInGroup, collapseOnTakeNewPosition;
    CGFloat _minimumHeight;
    NSPoint newPosition;
}

// Init and dealloc

- (id)initWithInspector:(OIInspector <OIConcreteInspector> *)anInspector inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry;
{
    OBPRECONDITION([anInspector conformsToProtocol:@protocol(OIConcreteInspector)]);

    if (!(self = [super init]))
        return nil;

    inspector = anInspector;
    _weak_inspectorRegistry = inspectorRegistry;
    
    _isExpanded = !anInspector.isCollapsible;
    self.interfaceType = anInspector.preferredInterfaceType;
    
    inspector.inspectorController = self;
    
    return self;
}

// API

@synthesize group = _weak_group;

- (void)setGroup:(OIInspectorGroup *)aGroup;
{
    if (_weak_group != aGroup) {
        _weak_group = aGroup;
        if (_weak_group != nil)
            [headingButton setNeedsDisplay:YES];
    }
}

- (OIInspector *)inspector;
{
    return inspector;
}

@synthesize inspectorRegistry = _weak_inspectorRegistry;

- (NSWindow *)window;
{
    return window;
}

- (OIInspectorHeaderView *)headingButton;
{
    return headingButton;
}

- (void)setExpanded:(BOOL)newState withNewTopLeftPoint:(NSPoint)topLeftPoint;
{
    if (!self.inspector.isCollapsible)
        return;
    
    switch (self.interfaceType) {
        case OIInspectorInterfaceTypeFloating:
            [self _setFloatingExpandedness:newState updateInspector:YES withNewTopLeftPoint:topLeftPoint animate:NO];
            break;
        case OIInspectorInterfaceTypeEmbedded:
            [self _setEmbeddedExpandedness:newState updateInspector:YES];
            break;
        // No default so the compiler warns if we add an item to the enum definition and don't handle it here
    }
}

- (NSString *)inspectorIdentifier;
{
    return inspector.inspectorIdentifier;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
    if ([item action] == @selector(toggleVisibleAction:)) {
        [item setState:_isExpanded && [_weak_group isVisible]];
    }
    return YES;
}

- (CGFloat)headingHeight;
{
    return NSHeight([headingButton frame]);
}

- (CGFloat)desiredHeightWhenExpanded;
{
    // PBS 22 Nov. 2016: headingButton is optional.
    // OBPRECONDITION(headingButton); // That is, -loadInterface must have been called.
    CGFloat headingButtonHeight = headingButton ? self.headingHeight : 0.0f;
    return NSHeight([[self _inspectorView] frame]) + headingButtonHeight;
}

- (void)toggleDisplay;
{
    if ([_weak_group isVisible]) {
        [self loadInterface]; // Load the UI and thus 'headingButton'
        [self headerViewDidToggleExpandedness:headingButton];
    } else {
        if (!_isExpanded) {
            [self loadInterface]; // Load the UI and thus 'headingButton'
            [self headerViewDidToggleExpandedness:headingButton];
        }
        [_weak_group showGroup];
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
    if (![_weak_group isVisible] || !_isExpanded)
        [self toggleDisplay];
    else
        [_weak_group orderFrontGroup]; 
}

- (BOOL)isVisible;
{
    return [_weak_group isVisible];
}

- (void)setBottommostInGroup:(BOOL)isBottom;
{
    if (isBottom == isBottommostInGroup)
        return;
    
    isBottommostInGroup = isBottom;
    if (window && !_isExpanded) {
        NSRect windowFrame = [window frame];
        NSRect headingFrame;
        
        headingFrame.origin = NSMakePoint(0, isBottommostInGroup ? 0.0f : OIInspectorSpaceBetweenButtons);
        headingFrame.size = [headingButton frame].size;
        [window setFrame:NSMakeRect(NSMinX(windowFrame), NSMaxY(windowFrame) - NSMaxY(headingFrame), NSWidth(headingFrame), NSMaxY(headingFrame)) display:YES animate:NO];
    }
}

- (void)toggleExpandednessWithNewTopLeftPoint:(NSPoint)topLeftPoint animate:(BOOL)animate;
{
    BOOL expanded = !_isExpanded;

    if (!inspector.isCollapsible)
        expanded = YES;

    switch (self.interfaceType) {
        case OIInspectorInterfaceTypeFloating:
            [self _setFloatingExpandedness:expanded updateInspector:YES withNewTopLeftPoint:topLeftPoint animate:animate];
            break;
        case OIInspectorInterfaceTypeEmbedded:
            [self _setEmbeddedExpandedness:expanded updateInspector:YES];
            break;
    }
}

- (void)updateExpandedness:(BOOL)allowAnimation; // call when the inspector sets its size internally by itself
{
    switch (self.interfaceType) {
        case OIInspectorInterfaceTypeFloating:
        {
            NSRect windowFrame = [window frame];
            [self _setFloatingExpandedness:_isExpanded
                           updateInspector:NO
                       withNewTopLeftPoint:NSMakePoint(NSMinX(windowFrame), NSMaxY(windowFrame))
                                   animate:allowAnimation];
        }
            break;
        case OIInspectorInterfaceTypeEmbedded:
            [self _setEmbeddedExpandedness:_isExpanded updateInspector:NO];
            break;
    }
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
    if ([[[self containerView] subviews] count] == 0) {
        [self populateContainerView];
    }
}

- (void)prepareWindowForDisplay;
{
    OBPRECONDITION(window != nil);  // -loadInterface should have been called by this point.
    OBPRECONDITION(self.interfaceType == OIInspectorInterfaceTypeFloating);
    
    if (window) {
        BOOL shouldBeExpandedBeforeDisplay = [[OIWorkspace sharedWorkspace] inspectorIsDisclosedForIdentifier:self.inspectorIdentifier];
        if (shouldBeExpandedBeforeDisplay != _isExpanded) {
            /* Expanding might cause our inspector to load its interface and lay itself out, thus informing us of the resize and reentering this method. So don't assume that _isExpanded is false because we set it that way in init.
             
             Stack trace (r170537):
             
             #186	0x0000000100738437 in -[OIInspectorController prepareWindowForDisplay] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniInspector/OIInspectorController.m:271
             #187	0x000000010075a6b0 in -[OITabbedInspector _layoutSelectedTabs] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniInspector/OITabbedInspector.m:721
             #188	0x0000000100754fb9 in -[OITabbedInspector awakeFromNib] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniInspector/OITabbedInspector.m:109
             #189	0x00007fff8ba07a41 in -[NSIBObjectData nibInstantiateWithOwner:topLevelObjects:] ()
             #190	0x00007fff8b9fdf73 in loadNib ()
             #191	0x00007fff8b9fd676 in +[NSBundle(NSNibLoading) _loadNibFile:nameTable:withZone:ownerBundle:] ()
             #192	0x00007fff8bb9e580 in -[NSBundle(NSNibLoading) loadNibFile:externalNameTable:withZone:] ()
             #193	0x00000001001a06ac in -[NSBundle(OAExtensions) loadNibNamed:owner:] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSBundle-OAExtensions.m:46
             #194	0x000000010075821a in -[OITabbedInspector inspectorView] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniInspector/OITabbedInspector.m:477
             #195	0x0000000100739939 in -[OIInspectorController _inspectorView] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniInspector/OIInspectorController.m:445
             #196	0x0000000100739e4a in -[OIInspectorController _setExpandedness:updateInspector:withNewTopLeftPoint:animate:] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniInspector/OIInspectorController.m:479
             #197	0x0000000100737bb0 in -[OIInspectorController toggleExpandednessWithNewTopLeftPoint:animate:] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniInspector/OIInspectorController.m:211
             #198	0x0000000100738437 in -[OIInspectorController prepareWindowForDisplay] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniInspector/OIInspectorController.m:271
             #199	0x0000000100743bd7 in -[OIInspectorGroup _showGroup] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniInspector/OIInspectorGroup.m:799
             #200	0x000000010073f39e in -[OIInspectorGroup showGroup] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniInspector/OIInspectorGroup.m:356
             #201	0x00007fff88734fb1 in -[NSObject performSelector:] ()
             #202	0x00007fff887392dc in -[NSArray makeObjectsPerformSelector:] ()
             #203	0x000000010074bf36 in +[OIInspectorRegistry tabShowHidePanels] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniInspector/OIInspectorRegistry.m:182
             #204	0x000000010075424a in -[OAApplication(OIExtensions) toggleInspectorPanel:] at /Volumes/SSD/OmniSource/MacTrunk/OmniGroup/Frameworks/OmniInspector/OAApplication-OIExtensions.m:25
             */
            
            NSRect windowFrame = [window frame];
            [self toggleExpandednessWithNewTopLeftPoint:NSMakePoint(NSMinX(windowFrame), NSMaxY(windowFrame)) animate:NO];
        }
    }
    [self updateInspector];
}

- (void)displayWindow;
{
    OBPRECONDITION(self.interfaceType == OIInspectorInterfaceTypeFloating);
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

    if (self.interfaceType == OIInspectorInterfaceTypeFloating && ![_weak_group isVisible])
        return;
    
    if (!_isExpanded)
        return;

    NSResponder *oldResponder = nil;
    @try {
        
        // Don't update the inspector if the list of objects to inspect hasn't changed. -inspectedObjectsOfClass: returns a pointer-sorted list of objects, so we can just to 'identical' on the array.
        NSArray *newInspectedObjects = [self.inspectorRegistry copyObjectsInterestingToInspector:inspector];
        NSString *newInspectionIdentifier = [self.inspectorRegistry inspectionIdentifierForCurrentInspectionSet];
        if (OFISEQUAL(currentInspectionIdentifier, newInspectionIdentifier) && ((newInspectedObjects == nil && currentlyInspectedObjects == nil) || [newInspectedObjects isIdenticalToArray:currentlyInspectedObjects])) {
            return;
        }
        
        // Record what was first responder in the inspector before we clear it.  We want to clear it since resigning first responder can cause controls to send actions and thus we want this happen *before* we change what would be affected by the action!
        oldResponder = [window firstResponder];
        
        // See if we're dealing with the field editor - if so, we really want to deal with the view it's handling editing for instead.
        if ([oldResponder isKindOfClass:[NSText class]]) {
            id responderDelegate = [(NSText *)oldResponder delegate];
            if ([responderDelegate isKindOfClass:[NSSearchField class]]) {
                oldResponder = nil;  // (Bug #32481)  don't make the window the first responder if user is typing in a search field because it ends editing
                
            } else if ([responderDelegate isKindOfClass:[NSView class]]) {
                OBASSERT([(NSView *)responderDelegate window] == window);  // We'd never have a first responder who is an NSText who has an NSView as their delegate, where this isn't a field editor situation, right?
                oldResponder = (NSResponder *)responderDelegate;
            }
        }
        
        // A nil oldResponder means "don't end editing"
        if (oldResponder != nil) {
            [window makeFirstResponder:window];
            
            // Since this is delayed, there is really no reasonable way for a NSResponder to refuse to resign here.  The selection has *already* changed!
            OBASSERT([window firstResponder] == window);
        }
        
        currentInspectionIdentifier = newInspectionIdentifier;
        currentlyInspectedObjects = newInspectedObjects; // takes ownership of the reference
        newInspectedObjects = nil;
        [inspector inspectObjects:currentlyInspectedObjects];
    } @catch (NSException *localException) {
        NSLog(@"-[%@ %@]: *** %@", [self class], NSStringFromSelector(_cmd), localException);
        [self inspectNothing];
    };

    // Restore the old first responder, unless it was a view that is no longer in the view hierarchy
    if ([oldResponder isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)oldResponder;
        if ([view window] != window)
            oldResponder = nil;
    }

    if (oldResponder != nil)
        [window makeFirstResponder:oldResponder];
}

- (void)inspectNothing;
{
    currentlyInspectedObjects = nil;
    currentInspectionIdentifier = nil;
    [inspector inspectObjects:nil]; // nil is handled specially (and differently than an empty array). Not a great API.
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
    
    
    [result setObject:self.inspectorIdentifier forKey:@"identifier"];
    [result setObject:([window isVisible] ? @"YES" : @"NO") forKey:@"isVisible"];
    [result setObject:[window description] forKey:@"window"];
    if ([window childWindows])
        [result setObject:[[window childWindows] description] forKey:@"childWindows"];
    if ([window parentWindow])
        [result setObject:[[window parentWindow] description] forKey:@"parentWindow"];
    return result;
}

#pragma mark - Internal

- (IBAction)toggleVisibleAction:(id)sender;
{
    BOOL didExpand = NO;
    if (!_isExpanded) {
        [self toggleDisplay];
        didExpand = YES;
    }
    if (![_weak_group isVisible]) {
        [_weak_group showGroup];
    } else if ([_weak_group isBelowOverlappingGroup]) {
        [_weak_group orderFrontGroup];
    } else if (!didExpand) {
        if ([_weak_group isOnlyExpandedMemberOfGroup:self])
            [_weak_group hideGroup];
        if ([[_weak_group inspectors] count] > 1) {
            [self loadInterface]; // Load the UI and thus 'headingButton'
            [self headerViewDidToggleExpandedness:headingButton];
        }
    }
}

- (void)populateContainerView;
{
    if (!inspector.wantsHeader && !inspector.isCollapsible) {
        [[self containerView] addSubview:[self _inspectorView]];
        return;
    }
    
    [self _buildHeadingView];
    
    if (!self.isExpanded && self.interfaceType == OIInspectorInterfaceTypeFloating) {
        [window setContentSize:headingButton.frame.size];
    }

    [[self containerView] addSubview:headingButton];
    
    headingBackground = [[OIInspectorHeaderBackground alloc] initWithFrame:[headingButton frame]];
    [headingBackground setAutoresizingMask:[headingButton autoresizingMask]];
    [headingBackground setHeaderView:headingButton];
    [[self containerView] addSubview:headingBackground positioned:NSWindowBelow relativeTo:nil];
}

#pragma mark - Private
// Added this so that Graffle could update it's header look to yosemite
// Can go away when that is resolved
- (Class)headingButtonClass;
{
    return [OIInspectorHeaderView class];
}

- (void)_buildHeadingView;
{
    OBPRECONDITION(headingButton == nil);

    headingButton = [[[self headingButtonClass] alloc] initWithFrame:NSMakeRect(0.0f, OIInspectorSpaceBetweenButtons,
                                                                            [self.inspectorRegistry inspectorWidth],
                                                                            inspector.defaultHeaderHeight)];
    [headingButton setTitle:[inspector displayName]];
    headingButton.titleContentHeight = OIInspectorStartingHeaderButtonHeight;

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

- (OIInspectorWindow *)buildWindow;
{
    return [[OIInspectorWindow alloc] initWithContentRect:NSMakeRect(500.0f, 300.0f, NSWidth([headingButton frame]), inspector.defaultHeaderHeight + OIInspectorSpaceBetweenButtons) styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
}

- (NSView *)containerView;
{
    if (self.interfaceType == OIInspectorInterfaceTypeFloating) {
        if (window == nil) {
            window = [self buildWindow];
            [window setDelegate:self];
            [window setBecomesKeyOnlyIfNeeded:YES];
        }
        
        return [window contentView];
    } else if (self.interfaceType == OIInspectorInterfaceTypeEmbedded) {
        if (self.embeddedContainerView == nil) {
            self.embeddedContainerView = [[NSView alloc] init];
        }
        
        return self.embeddedContainerView;
    } else {
        return nil;
    }
}

- (NSView *)_inspectorView;
{
    NSView *inspectorView = inspector.view;
    
    if (!loadedInspectorView) {
        if ([inspector respondsToSelector:@selector(inspectorMinimumHeight)]) {
            _minimumHeight = [inspector inspectorMinimumHeight];
        } else {
            _minimumHeight = [inspectorView frame].size.height;
        }
        
	NSSize size = [inspectorView frame].size;
	OBASSERT(size.width <= [self.inspectorRegistry inspectorWidth], @"size is %1.2f, inspector registry wants %1.2f", size.width, [self.inspectorRegistry inspectorWidth]); // OK to make inspectors wider, but probably indicates a problem if the nib is wider than the global inspector width
        if (size.width > [self.inspectorRegistry inspectorWidth]) {
            NSLog(@"Inspector %@ is wider (%g) than grouped width (%g)", self.inspectorIdentifier, size.width, [self.inspectorRegistry inspectorWidth]);
        }
	size.width = [self.inspectorRegistry inspectorWidth];
	[inspectorView setFrameSize:size];
	
        loadedInspectorView = YES;
    }
    return inspectorView;
}

- (void)_setFloatingExpandedness:(BOOL)expanded updateInspector:(BOOL)updateInspector withNewTopLeftPoint:(NSPoint)topLeftPoint animate:(BOOL)animate;
{
    OBPRECONDITION(self.interfaceType == OIInspectorInterfaceTypeFloating);
    NSView *view = [self _inspectorView];
    BOOL hadVisibleInspectors = [self.inspectorRegistry hasVisibleInspector];

    _isExpanded = expanded;
    _isSettingExpansion = YES;
    [_weak_group setScreenChangesEnabled:NO];
    [headingButton setExpanded:_isExpanded];

    CGFloat additionalHeaderHeight;
    
    if (_isExpanded) {

        if (updateInspector) {
            // If no inspectors were previously visible, the inspector registry's selection set may not be up-to-date, so tell it to update
            // (an alternate approach would be to have the registry keep track of whether or not it was up to date, and here we would simply tell the registry to update if it needed to, rather than us basing this off of whether or not any inspectors were previously visible, thus requiring us to know that -[OIInspectorRegistry _recalculateInspectorsAndInspectWindow] doesn't do anything if no inspectors are visible)
            if (!hadVisibleInspectors)
                [OIInspectorRegistry updateInspectorForWindow:[[NSApplication sharedApplication] mainWindow]];
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

        viewFrame.origin.x = (CGFloat)floor((NSWidth(newContentRect) - NSWidth(viewFrame)) / 2.0);
        viewFrame.origin.y = 0;

        additionalHeaderHeight = [inspector additionalHeaderHeight];
        
        [view setFrame:viewFrame];
        [view setAutoresizingMask:NSViewNotSizable];
        [[self containerView] addSubview:view positioned:NSWindowBelow relativeTo:headingButton];
        [window setFrame:windowFrame display:YES animate:animate];
        [view setAutoresizingMask:NSViewHeightSizable | NSViewMinXMargin | NSViewMaxXMargin];

        [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceWillChangeNotification object:self];
        [[OIWorkspace sharedWorkspace] setInspectorIsDisclosed:YES forIdentifier:self.inspectorIdentifier];
        [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceDidChangeNotification object:self];

    } else {
	[window makeFirstResponder:window];

        [view setAutoresizingMask:NSViewNotSizable];
	
        NSRect headingFrame;
        headingFrame.origin = NSMakePoint(0, isBottommostInGroup ? 0.0f : OIInspectorSpaceBetweenButtons);
        if (_weak_group == nil)
            headingFrame.size = [headingButton frame].size;
        else
            headingFrame.size = NSMakeSize([self.inspectorRegistry inspectorWidth], [headingButton frame].size.height);
        NSRect headingWindowFrame = [window frameRectForContentRect:headingFrame];
        headingWindowFrame.origin.x = topLeftPoint.x;
        headingWindowFrame.origin.y = topLeftPoint.y - headingWindowFrame.size.height;
        [window setFrame:headingWindowFrame display:YES animate:animate];
        [view removeFromSuperview];

        additionalHeaderHeight = 0;
        
        if (updateInspector)
            [self inspectNothing];

        [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceWillChangeNotification object:self];
        [[OIWorkspace sharedWorkspace] setInspectorIsDisclosed:NO forIdentifier:self.inspectorIdentifier];
            [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceDidChangeNotification object:self];
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
    
    [self.inspectorRegistry configurationsChanged];
    
    [_weak_group setScreenChangesEnabled:YES];
    _isSettingExpansion = NO;
    
    [self _postExpandednessChangedNotification];
}

- (void)_setEmbeddedExpandedness:(BOOL)expanded updateInspector:(BOOL)updateInspector;
{
    OBPRECONDITION(self.interfaceType == OIInspectorInterfaceTypeEmbedded);
    
    if (expanded == _isExpanded)
        return;
    BOOL hadVisibleInspector = [self.inspectorRegistry hasVisibleInspector];
    _isExpanded = expanded;
    [headingButton setExpanded:_isExpanded];

    if (updateInspector) {
        if (!hadVisibleInspector) {
            [self.inspectorRegistry updateInspectionSetImmediatelyAndUnconditionallyForWindow:[[self containerView] window]];
        }
        [self updateInspector];
    }
    
    NSView *inspectorView = [self _inspectorView];
    if (expanded) {
        // Ensure the container view has some sort of reasonable frame (so the autoresizing masks work). It'll get re-laid-out later.
        if (NSEqualRects(NSZeroRect, [[self containerView] frame])) {
            [[self containerView] setFrame:NSMakeRect(0, 0, 200, 200)];
        }
        
        [[self containerView] addSubview:inspectorView];
        NSRect containerBounds = [[self containerView] bounds];
        CGFloat headerHeight = NSHeight(headingBackground.frame);
        inspectorView.frame = (NSRect){
            .origin = (NSPoint){
                .x = 0,
                .y = [[self containerView] isFlipped] ? headerHeight : 0
            },
            .size = (NSSize){
                .width = NSWidth(containerBounds),
                .height = MAX(NSHeight(containerBounds) - headerHeight, 0)
            }
        };
        inspectorView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    } else {
        [inspectorView removeFromSuperview];
    }
    
    for (NSView *view in @[ headingButton, headingBackground] ){
        NSRect frame = view.frame;
        frame.origin.y = NSMaxY([[self containerView] bounds]) - [self headingHeight];
        view.frame = frame;
    }
    
    [self _postExpandednessChangedNotification];
}

- (void)_postExpandednessChangedNotification;
{
    NSDictionary *userInfo = @{ @"isExpanded" : @(_isExpanded) };
    NSNotification *notification = [[NSNotification alloc] initWithName:OIInspectorControllerDidChangeExpandednessNotification
                                                                  object:self
                                                                userInfo:userInfo];
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

- (void)_saveInspectorHeight;
{
    NSSize size = [[self _inspectorView] frame].size;

    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceWillChangeNotification object:self];
    [[OIWorkspace sharedWorkspace] setHeight:size.height forInspectorIdentifier:self.inspectorIdentifier];
    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceDidChangeNotification object:self];
    [[OIWorkspace sharedWorkspace] save];
}

- (BOOL)_groupCanBeginResizingOperation;
{
    if (_weak_group) {
        return [_weak_group canBeginResizingOperation];
    } else {
        return (self.interfaceType == OIInspectorInterfaceTypeEmbedded);
    }
}

#pragma mark NSWindow delegate

- (void)windowDidMove:(NSNotification *)notification;
{
    OIInspectorRegistry *registry = self.inspectorRegistry;
    [registry configurationsChanged]; 
}

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
    NSWindow *mainWindow = [[NSApplication sharedApplication] mainWindow];
    NSResponder *nextResponder = [mainWindow firstResponder];
    if (nextResponder == nil)
        nextResponder = mainWindow;
    
    NSUndoManager *(^getUndoManager)(id object) = ^NSUndoManager *(id object){
        if ([object respondsToSelector:@selector(undoManager)])
            return [object undoManager];
        
        if ([nextResponder respondsToSelector:@selector(delegate)]) {
            id delegate = [(id)nextResponder delegate];
            if ([delegate respondsToSelector:@selector(undoManager)]) {
                return [delegate undoManager];
            }
        }
        return nil;
    };
    
    NSUndoManager *undoManager = nil;
    do {
        undoManager = getUndoManager(nextResponder);
        nextResponder = [nextResponder nextResponder];
    } while (nextResponder && !undoManager);
    
    return undoManager;
}

#pragma mark OIInspectorWindow delegate

- (void)windowWillBeginResizing:(NSWindow *)resizingWindow;
{
    OBASSERT(resizingWindow == window);
    [_weak_group inspectorWillStartResizing:self];
}

- (void)windowDidFinishResizing:(NSWindow *)resizingWindow;
{
    OBASSERT(resizingWindow == window);
    [_weak_group inspectorDidFinishResizing:self];
}

/*"
 If you call this method, you must also call -windowDidFinishResizing: after the resize is actually complete. The reason is that this method calls a corresponding method on the inspector group which sets up some resizing stuff that must be cleaned up when the resizing is complete.
 Good news, everybody! OIInspectorWindow automatically calls -windowDidFinishResizing: at the end of -setFrame:display:animate:, so if that's the method you use to perform the actual resize, you don't need to call -windowDidFinishResizing: yourself.
"*/
- (NSRect)windowWillResizeFromFrame:(NSRect)fromRect toFrame:(NSRect)toRect;
{
    NSRect result;

    if ([_weak_group ignoreResizing]) {
        return toRect;
    }

    NSRect newContentRect = [window contentRectForFrameRect:toRect];
    
    if (_isExpanded && !_isSettingExpansion) {
        if ([inspector respondsToSelector:@selector(inspectorMinimumHeight)])
            _minimumHeight = [inspector inspectorMinimumHeight];

        if (NSHeight(newContentRect) < _minimumHeight)
            newContentRect.size.height = _minimumHeight;
    }
    newContentRect.size.width = [self.inspectorRegistry inspectorWidth];
    
    toRect = [window frameRectForContentRect:newContentRect];
    
    if (_isExpanded && !_isSettingExpansion) {
        toRect.origin.y += NSHeight(fromRect) - NSHeight(toRect);
        toRect.size.height = NSHeight(fromRect);
    }
    
    if (_weak_group != nil) {
        result = [_weak_group inspector:self willResizeToFrame:toRect isSettingExpansion:_isSettingExpansion];
	OBASSERT(result.size.width == toRect.size.width); // Not allowed to width-size inspectors ever!
    } else
        result = toRect;
    
    return result;
}

#pragma mark OIInspectorHeaderViewDelegateProtocol

- (BOOL)headerViewShouldDisplayExpandButton:(OIInspectorHeaderView *)view
{
    return inspector.isCollapsible;
}

- (BOOL)headerViewShouldDisplayCloseButton:(OIInspectorHeaderView *)view;
{
    return (self.interfaceType == OIInspectorInterfaceTypeFloating && [_weak_group isHeadOfGroup:self]);
}

- (BOOL)headerViewShouldAllowDragging:(OIInspectorHeaderView *)view;
{
    return (self.interfaceType == OIInspectorInterfaceTypeFloating);
}

- (CGFloat)headerViewDraggingHeight:(OIInspectorHeaderView *)view;
{
    NSRect myGroupFrame;
    
    if (!window || ![_weak_group getGroupFrame:&myGroupFrame]) {
        OBASSERT_NOT_REACHED("Can't calculate headerViewDraggingHeight");
        return 1.0f;
    }
    
    return NSMaxY([window frame]) - myGroupFrame.origin.y;
}

- (void)headerViewDidBeginDragging:(OIInspectorHeaderView *)view;
{
    OBPRECONDITION([self headerViewShouldAllowDragging:view]);
    [_weak_group detachFromGroup:self];
}

- (NSRect)headerView:(OIInspectorHeaderView *)view willDragWindowToFrame:(NSRect)aFrame onScreen:(NSScreen *)screen;
{
    aFrame = [_weak_group fitFrame:aFrame onScreen:screen forceVisible:NO];
    aFrame = [_weak_group snapToOtherGroupWithFrame:aFrame];
    return aFrame;
}

- (void)headerViewDidEndDragging:(OIInspectorHeaderView *)view toFrame:(NSRect)aFrame;
{
    OBPRECONDITION([self headerViewShouldAllowDragging:view]);
    [_weak_group windowsDidMoveToFrame:aFrame];
}

- (void)headerViewDidToggleExpandedness:(OIInspectorHeaderView *)senderButton;
{
    OBPRECONDITION(senderButton);
    
    if ([self _groupCanBeginResizingOperation]) {
        NSRect windowFrame = [window frame];
        [self toggleExpandednessWithNewTopLeftPoint:NSMakePoint(NSMinX(windowFrame), NSMaxY(windowFrame)) animate:YES];
    } else {
        // try again when the current resizing operation may be done
        [self performSelector:@selector(headerViewDidToggleExpandedness:) withObject:senderButton afterDelay:0.1];
    }
}

- (void)headerViewDidClose:(OIInspectorHeaderView *)view;
{
    [_weak_group hideGroup];
}

@end
