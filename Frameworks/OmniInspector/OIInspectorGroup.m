// Copyright 2002-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIInspectorGroup.h>

#import <AppKit/AppKit.h>
#import <OmniAppKit/OAColorWell.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniInspector/OIInspector.h>
#import <OmniInspector/OIInspectorHeaderView.h>
#import <OmniInspector/OIWorkspace.h>

#import "OIInspectorController-Internal.h"

RCS_ID("$Id$");

@implementation OIInspectorGroup
{
    NSMutableArray <OIInspectorController *> *_inspectors;
    OIInspectorController *_resizingInspector;
    struct {
        unsigned int	ignoreResizing:1;
        unsigned int	isSettingExpansion:1;
        unsigned int	isShowing:1;
        unsigned int	screenChangesEnabled:1;
        unsigned int	hasPositionedWindows:1;
    } _inspectorGroupFlags;
}

#define CONNECTION_DISTANCE_SQUARED 225.0
#define CONNECTION_VERTICAL_DISTANCE	(5.0)
#define ANIMATION_VERTICAL_DISTANCE	(30.0)

static NSMenu *dynamicMenu;
static NSUInteger dynamicMenuItemIndex;
static NSUInteger dynamicMenuItemCount;
static BOOL useWorkspaces = NO;
static BOOL useASeparateMenuForWorkspaces = NO;

+ (void)enableWorkspaces;
{
    useWorkspaces = YES;
}

+ (void)useASeparateMenuForWorkspaces;
{
    useASeparateMenuForWorkspaces = YES;
}

+ (BOOL)isUsingASeparateMenuForWorkspaces;
{
    return useASeparateMenuForWorkspaces;
}

+ (void)setDynamicMenuPlaceholder:(NSMenuItem *)placeholder;
{
    dynamicMenu = [placeholder menu];
    dynamicMenuItemIndex = [[dynamicMenu itemArray] indexOfObject:placeholder];
    dynamicMenuItemCount = 0;
    
    [dynamicMenu removeItemAtIndex:dynamicMenuItemIndex];
}

// Init and dealloc

- init;
{
    if (!(self = [super init]))
        return nil;
    
    _inspectors = [[NSMutableArray alloc] init];
    _inspectorGroupFlags.screenChangesEnabled = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screensDidChange:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (OIInspectorController *controller in _inspectors) {
        controller.group = nil;
    }
}

// API

- (BOOL)defaultGroupVisibility;
{
    for (OIInspectorController *controller in _inspectors) {
        if ([controller.inspector defaultVisibilityState] != OIHiddenVisibilityState)
            return YES;
    }
    return NO;
}

- (void)clear;
{
    [self hideGroup];
    for (OIInspectorController *controller in _inspectors) {
        controller.group = nil;
    }
    [_inspectors removeAllObjects];
}

- (void)hideGroup;
{
    if (![self isVisible])
        return;
    [self _hideGroup];
}

- (void)showGroup;
{
    if ([self isVisible]) {
        [self orderFrontGroup];
    } else {
        [self _showGroup];
    }
}

- (void)orderFrontGroup;
{
    // make sure group is visible on screen
    [self screensDidChange:nil];
    
    [[[_inspectors firstObject] window] orderFront:self];
}

- (void)addInspector:(OIInspectorController *)aController;
{
    if ([_inspectors count]) {
        NSWindow *window = [aController window];
        OIInspectorController *bottomInspector = [_inspectors lastObject];
        
        _inspectorGroupFlags.ignoreResizing = YES;
        [bottomInspector setBottommostInGroup:NO];
        _inspectorGroupFlags.ignoreResizing = NO;
        
        NSRect groupFrame;
        if ([self getGroupFrame:&groupFrame])
            [window setFrameTopLeftPoint:groupFrame.origin];
    } 
    [aController setGroup:self];
    [_inspectors addObject:aController];
}

- (NSRect)inspector:(OIInspectorController *)aController willResizeToFrame:(NSRect)aFrame isSettingExpansion:(BOOL)calledIsSettingExpansion;
{
    if (_inspectorGroupFlags.ignoreResizing)
        return aFrame;

    NSRect result = [self calculateForInspector:aController willResizeToFrame:aFrame moveOthers:NO];
    _inspectorGroupFlags.isSettingExpansion = calledIsSettingExpansion;

    [self inspectorWillStartResizing:aController];

    return result;
}

- (void)inspectorWillStartResizing:(OIInspectorController *)inspectorController;
{
    if ((_resizingInspector == nil) && [[inspectorController window] isVisible]) {
        _resizingInspector = inspectorController;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(controllerWindowDidResize:) name:NSWindowDidResizeNotification object:[inspectorController window]];
    }
}

- (void)inspectorDidFinishResizing:(OIInspectorController *)inspectorController;
{
    if (inspectorController == _resizingInspector) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResizeNotification object:[inspectorController window]];
        _resizingInspector = nil;
        
        [[OIInspectorRegistry inspectorRegistryForMainWindow] configurationsChanged];
    }
}

- (void)detachFromGroup:(OIInspectorController *)aController;
{
    NSUInteger originalIndex = [_inspectors indexOfObject:aController];
    if (originalIndex == NSNotFound || originalIndex == 0)
        return;

    _inspectorGroupFlags.ignoreResizing = YES;
    [[_inspectors objectAtIndex:(originalIndex - 1)] setBottommostInGroup:YES];
    _inspectorGroupFlags.ignoreResizing = NO;

#ifdef OMNI_ASSERTIONS_ON
    NSWindow *topWindow = [[_inspectors firstObject] window];
#endif
    OIInspectorGroup *newGroup = [[OIInspectorGroup alloc] init];
    newGroup.inspectorRegistry = self.inspectorRegistry;
    [self.inspectorRegistry addExistingGroup:newGroup];
    
    NSUInteger inspectorCount = [_inspectors count];
    
    [self disconnectWindows];
    
    for (NSUInteger inspectorIndex = originalIndex; inspectorIndex < inspectorCount; inspectorIndex++) {
        OIInspectorController *controller = _inspectors[inspectorIndex];
        [newGroup addInspector:controller];
    }
    [_inspectors removeObjectsInRange:NSMakeRange(originalIndex, inspectorCount - originalIndex)];
    
    [self connectWindows];
    [newGroup connectWindows];
    [[aController window] resetCursorRects]; // for the close buttons to highlight correctly in all cases
    
    OBPOSTCONDITION([_inspectors count] == originalIndex);
    OBPOSTCONDITION([[topWindow childWindows] count] == (originalIndex - 1));
}

- (BOOL)isHeadOfGroup:(OIInspectorController *)aController;
{
    return aController == [_inspectors firstObject];
}

- (BOOL)isOnlyExpandedMemberOfGroup:(OIInspectorController *)aController;
{
    for (OIInspectorController *controller in _inspectors) {
        if (controller != aController && [controller isExpanded])
            return NO;
    }
    return YES;
}

- (NSArray <OIInspectorController *> *)inspectors;
{
    return _inspectors;
}

- (BOOL)getGroupFrame:(NSRect *)resultptr;
{
    BOOL foundOne = NO;
    NSRect result = NSZeroRect;
    
    for (OIInspectorController *inspector in _inspectors) {
        NSWindow *aWindow = [inspector window];
        if (!aWindow)
            continue;
        NSRect rect = [aWindow frame];
        if (foundOne) {
            result = NSUnionRect(result, rect);
        } else {
            foundOne = YES;
            result = rect;
        }
    }
    
    if (foundOne)
        *resultptr = result;
    return foundOne;
}

- (BOOL)isVisible;
{
    if (_inspectorGroupFlags.isShowing)
        return YES;
    else
        return [[[_inspectors firstObject] window] isVisible];
}

- (BOOL)isBelowOverlappingGroup;
{
    NSRect groupFrame;
    if (![self getGroupFrame:&groupFrame])
        return NO;
    
    NSArray *orderedGroups = [self.inspectorRegistry groups];
    NSUInteger groupIndex, groupCount = [orderedGroups count];

    for (groupIndex = [orderedGroups indexOfObjectIdenticalTo:self] + 1; groupIndex < groupCount; groupIndex++) {
        OIInspectorGroup *otherGroup = [orderedGroups objectAtIndex:groupIndex];
        NSRect otherFrame;
        
        if ([otherGroup getGroupFrame:&otherFrame] && NSIntersectsRect(groupFrame, otherFrame))
            return YES;
    }
    return NO;
}

- (BOOL)isSettingExpansion;
{
    return _inspectorGroupFlags.isSettingExpansion;
}

- (CGFloat)singlePaneExpandedMaxHeight;
{
    CGFloat result = 0.0f;
    CGFloat totalHeight = OIInspectorStartingHeaderButtonHeight;

    for (OIInspectorController *inspector in _inspectors) {
        CGFloat inspectorDesired = [inspector desiredHeightWhenExpanded];
        if (inspector.headingButton) {
            totalHeight = inspector.headingButton.heightNeededWhenExpanded;
        }

        if (inspectorDesired > result)
            result = inspectorDesired;
    }
    return (result + totalHeight * ([_inspectors count] - 1));
}

- (BOOL)ignoreResizing;
{
    return _inspectorGroupFlags.ignoreResizing;
}

- (BOOL)canBeginResizingOperation;
{
    return (_resizingInspector == nil);
}

- (BOOL)screenChangesEnabled;
{
    return _inspectorGroupFlags.screenChangesEnabled;
}

- (void)setScreenChangesEnabled:(BOOL)yn;
{
    _inspectorGroupFlags.screenChangesEnabled = yn;
}

- (void)setFloating:(BOOL)yn;
{
    for (OIInspectorController *inspector in _inspectors) {
        NSWindow *window = [inspector window];
        [window setLevel:yn ? NSFloatingWindowLevel : NSNormalWindowLevel];
    }
}

#define SCREEN_BUFFER (40.0f)

- (NSRect)fitFrame:(NSRect)aFrame onScreen:(NSScreen *)screen forceVisible:(BOOL)forceVisible;
{
    CGFloat buffer = (CGFloat)(forceVisible ? 1e9 : SCREEN_BUFFER);
    NSRect screenRect = [screen visibleFrame];
    
    if (NSHeight(aFrame) > NSHeight(screenRect))
        aFrame.origin.y = (CGFloat)floor(NSMaxY(screenRect) - NSHeight(aFrame));
    else if (NSMaxY(aFrame) > NSMaxY(screenRect) && NSMaxY(aFrame) - NSMaxY(screenRect))
        aFrame.origin.y = (CGFloat)floor(NSMaxY(screenRect) - NSHeight(aFrame));
    else if (NSMinY(aFrame) < NSMinY(screenRect) && NSMinY(screenRect) - NSMinY(aFrame) < buffer)
        aFrame.origin.y = (CGFloat)ceil(NSMinY(screenRect));
                            
    if (NSMaxX(aFrame) > NSMaxX(screenRect) && NSMaxX(aFrame) - NSMaxX(screenRect) < buffer)
        aFrame.origin.x = (CGFloat)floor(NSMaxX(screenRect) - NSWidth(aFrame));
    else if (NSMinX(aFrame) < NSMinX(screenRect) && NSMinX(screenRect) - NSMinX(aFrame) < buffer)
        aFrame.origin.x = (CGFloat)ceil(NSMinX(screenRect));
    
    return aFrame;
}

- (void)setTopLeftPoint:(NSPoint)aPoint;
{
    NSWindow *topWindow = [[_inspectors firstObject] window];
    NSUInteger index, count = [_inspectors count];

    [topWindow setFrameTopLeftPoint:aPoint];
    for (index = 1; index < count; index++) {
        NSWindow *bottomWindow = [[_inspectors objectAtIndex:index] window];
        
        [bottomWindow setFrameTopLeftPoint:[topWindow frame].origin];
        topWindow = bottomWindow;
    }
}

- (NSRect)snapToOtherGroupWithFrame:(NSRect)aRect;
{
    id closestSoFar = nil;
    NSRect closestFrame = NSZeroRect;
    CGFloat closestDistance = CGFLOAT_MAX;
    CGFloat position;

    // Snap to top or bottom of other group
    for (OIInspectorGroup *otherGroup in self.inspectorRegistry.existingGroups) {
        NSRect otherGroupFrame;
            
        if (self == otherGroup || ![otherGroup isVisible] || ![otherGroup getGroupFrame:&otherGroupFrame])
            continue;
        if ([self willConnectToBottomOfGroup:otherGroup withFrame:aRect]) {
            aRect.origin.x = otherGroupFrame.origin.x;
            aRect.origin.y = otherGroupFrame.origin.y - aRect.size.height - OIInspectorSpaceBetweenButtons;
            return aRect;
        } else if ([self willConnectToTopOfGroup:otherGroup withFrame:aRect]) {
            aRect.origin.x = otherGroupFrame.origin.x;
            aRect.origin.y = NSMaxY(otherGroupFrame) + OIInspectorSpaceBetweenButtons;
            return aRect;
        } else if ([otherGroup willInsertInGroup:self withFrame:aRect index:NULL position:&position]) {
            aRect.origin.y = (CGFloat)floor(position + OIInspectorStartingHeaderButtonHeight / 2) - aRect.size.height;
            return aRect;
        }
    }

    // Check for snap to side of other group
    
    for (OIInspectorGroup *otherGroup in self.inspectorRegistry.existingGroups) {
        NSRect otherFrame;
        CGFloat distance;

        if (self == otherGroup || ![otherGroup isVisible] || ![otherGroup getGroupFrame:&otherFrame])
            continue;
            
        if (NSMinY(otherFrame) > NSMaxY(aRect) || NSMaxY(otherFrame) < NSMinY(aRect))
            distance = ABS(NSMinX(otherFrame) - NSMinX(aRect));
        else
            distance = MIN(ABS(NSMinX(otherFrame) - OIInspectorColumnSpacing - NSMaxX(aRect)), ABS(NSMaxX(otherFrame) + OIInspectorColumnSpacing - NSMinX(aRect)));
            
        if (distance < closestDistance || (distance == closestDistance && ((NSMinY(closestFrame) > NSMinY(otherFrame)) || NSMinY(closestFrame) < NSMinY(aRect)) && (NSMinY(otherFrame) > NSMaxY(aRect)))) {
            closestDistance = distance;
            closestSoFar = otherGroup;
            closestFrame = otherFrame;
        }
    }
    
    // Check for snap to side of document window
    for (NSDocument *document in [[NSDocumentController sharedDocumentController] documents]) {
        for (NSWindowController *windowController in [document windowControllers]) {
            NSWindow *window = windowController.window;
            
            if (!window || ![window isVisible])
                continue;
            
            NSRect windowFrame = [window frame];
            CGFloat distance = MIN(ABS(NSMinX(windowFrame) - OIInspectorColumnSpacing - NSMaxX(aRect)), ABS(NSMaxX(windowFrame) + OIInspectorColumnSpacing - NSMinX(aRect)));

            if (distance < closestDistance) {
                closestDistance = distance;
                closestSoFar = window;
                closestFrame = windowFrame;
            }
        } 
    }
    
    if (closestDistance < 15.0f) {
        BOOL normalWindow = [closestSoFar isKindOfClass:[NSWindow class]];
        
        if (ABS(NSMinX(closestFrame) - NSMinX(aRect)) < 15.0f) {
            aRect.origin.x = NSMinX(closestFrame);
            
            if (!normalWindow) {
                CGFloat belowClosest = NSMaxY(closestFrame) - [closestSoFar singlePaneExpandedMaxHeight] - OIInspectorStartingHeaderButtonHeight;
                
                if (ABS(NSMaxY(aRect) - belowClosest) < 10.0f)
                    aRect.origin.y -= (NSMaxY(aRect) - belowClosest);
            }
            
        } else {
            NSRect frame = NSInsetRect(closestFrame, -1.0f, -1.0f);
            if (ABS(NSMinX(frame) - OIInspectorColumnSpacing - NSMaxX(aRect)) < ABS(NSMaxX(frame) + OIInspectorColumnSpacing - NSMinX(aRect)))
                aRect.origin.x = NSMinX(frame) - NSWidth(aRect) - OIInspectorColumnSpacing;
            else
                aRect.origin.x = NSMaxX(frame) + OIInspectorColumnSpacing;
        }
    }    


    // TJW: This seems to do nothing (no side effects, no return value).  What was it supposed to do?
#if 0
    {
        OIInspectorGroup *closestGroupWithoutSnapping = nil;
        float closestVerticalDistance = 1e10;

        count = [self.inspectorRegistry.existingGroups count];
        for (index = 0; index < count; index++) {
            OIInspectorGroup *otherGroup = [self.inspectorRegistry.existingGroups objectAtIndex:index];
            NSRect otherFrame;

            if (self == otherGroup || ![otherGroup isVisible] || ![otherGroup getGroupFrame:&otherFrame])
                continue;

            if ([self _frame:aRect overlapsHorizontallyEnoughToConnectToFrame:otherFrame]) {
                float verticalDistance = fabs(NSMinY(otherFrame) - NSMaxY(aRect));
                verticalDistance = MIN(verticalDistance, fabs(NSMinY(aRect) - NSMaxY(otherFrame)));
                if (verticalDistance < closestVerticalDistance) {
                    closestVerticalDistance = verticalDistance;
                    closestGroupWithoutSnapping = otherGroup;
                }
            }
        }
    }
#endif
    
    return aRect;
}

- (void)windowsDidMoveToFrame:(NSRect)aFrame;
{
    OBRetainAutorelease(self); // Make sure we don't get deallocated during this.

    for (OIInspectorGroup *otherGroup in self.inspectorRegistry.existingGroups) {
        if (self == otherGroup || ![otherGroup isVisible])
            continue;
        if ([self willConnectToBottomOfGroup:otherGroup withFrame:aFrame]) {
            [self connectToBottomOfGroup:otherGroup];
            break;
        } else if ([self willConnectToTopOfGroup:otherGroup withFrame:aFrame]) {
            [otherGroup connectToBottomOfGroup:self];
            break;
        } else if ([otherGroup insertGroup:self withFrame:aFrame]) {
            [_inspectors removeAllObjects];
            break;
        }
    }
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *result = [super debugDictionary];
    NSMutableArray *inspectorInfo = [NSMutableArray array];
    
    for (OIInspectorController *inspector in _inspectors)
        [inspectorInfo addObject:[inspector debugDictionary]];
    
    [result setObject:inspectorInfo forKey:@"inspectors"];
        
    [result setObject:([self isVisible] ? @"YES" : @"NO") forKey:@"isVisible"];

    return result;
}

#pragma mark - Internal

- (void)_showGroup;
{
    OBASSERT([_inspectors count]);
    if (![_inspectors count])
        return;
    
    NSUInteger index, count = [_inspectors count];

    _inspectorGroupFlags.isShowing = YES;

    OIInspectorRegistry *inspectorRegistry = [OIInspectorRegistry inspectorRegistryForMainWindow];
    // Remember whether there were previously any visible inspectors
    BOOL hadVisibleInspector = [inspectorRegistry hasVisibleInspector];
    
    // Position windows if we haven't already
    if (!_inspectorGroupFlags.hasPositionedWindows) {
        _inspectorGroupFlags.hasPositionedWindows = YES;
        
        OIWorkspace *sharedWorkspace = [OIWorkspace sharedWorkspace];
        for (index = 0; index < count; index++) {
            OIInspectorController *controller = _inspectors[index];
            NSString *identifier = controller.inspectorIdentifier;

            [controller loadInterface];
            if (controller.interfaceType == OIInspectorInterfaceTypeFloating) {
                NSWindow *window = [controller window];
                OBASSERT(window);
                if (!index) {
                    NSPoint position = [sharedWorkspace floatingInspectorPositionForIdentifier:identifier];
                    if (NSEqualPoints(position, NSZeroPoint) == NO)
                        [window setFrameTopLeftPoint:position];
                }
            }
        }
    }

    // If there were previously no visible inspectors, update the inspection set.  We need to do this now (not queued) and even if there are no inspectors visible (since there aren't).  The issue is that the inspection set may hold pointers to objects from closed documents that are partially dead or otherwise invalid.  We want the inspectors to show the right stuff when they come on screen anyway rather than coming up and then getting updated.  We do NOT want to tell the inspectors about the updated inspection set immediately (+updateInspectionSetImmediatelyAndUnconditionally doesn't) since -prepareWindowForDisplay will do that and it would just be redundant.
    if (!hadVisibleInspector)
        [OIInspectorRegistry updateInspectionSetImmediatelyAndUnconditionallyForWindow:[[NSApplication sharedApplication] mainWindow]];
    
    index = count;
    while (index--) {
        OIInspectorController *inspectorcontroller = _inspectors[index];
        if (inspectorcontroller.inspector.preferredInterfaceType == OIInspectorInterfaceTypeFloating)
            [_inspectors[index] prepareWindowForDisplay];
    }
    [self setTopLeftPoint:[self topLeftPoint]];

    // to make sure they are placed visibly and ordered correctly
    [self screensDidChange:nil];
    
    [_inspectors enumerateObjectsUsingBlock:^(OIInspectorController *inspectorController, NSUInteger idx, BOOL *stop) {
        if (inspectorController.inspector.preferredInterfaceType == OIInspectorInterfaceTypeFloating)
            [inspectorController displayWindow];
    }];
    
    [self connectWindows];
    _inspectorGroupFlags.isShowing = NO;

    [inspectorRegistry configurationsChanged];
}

#pragma mark - Ugly API

- (void)_setHasPositionedWindows;
{
    _inspectorGroupFlags.hasPositionedWindows = YES;
}

#pragma mark - Private

- (void)_hideGroup;
{
    [self disconnectWindows];
    
    for (OIInspectorController *inspector in _inspectors) {
        OBASSERT([[inspector window] isReleasedWhenClosed] == NO);
        [[inspector window] close];
    }
    
    [[OIInspectorRegistry inspectorRegistryForMainWindow] configurationsChanged];
}

- (void)disconnectWindows;
{
    NSWindow *topWindow = [[_inspectors firstObject] window];
    NSUInteger index = [_inspectors count];
    
    OBPRECONDITION(!topWindow || ([[topWindow childWindows] count] == index-1));
    while (index-- > 1) 
        [topWindow removeChildWindow:[[_inspectors objectAtIndex:index] window]];
        
    OBPOSTCONDITION([[topWindow childWindows] count] == 0);
}

- (void)connectWindows;
{
    NSUInteger index, count = [_inspectors count];
    NSWindow *topWindow = [[_inspectors firstObject] window];
    NSWindow *lastWindow = topWindow;
    
    if (![topWindow isVisible])
        return;
    
    OBPRECONDITION([[topWindow childWindows] count] == 0);
    for (index = 1; index < count; index++) {
        NSWindow *window = [[_inspectors objectAtIndex:index] window];
        
        [window orderWindow:NSWindowAbove relativeTo:[lastWindow windowNumber]];
        [topWindow addChildWindow:window ordered:NSWindowAbove];
        lastWindow = window;
    }
}

- (NSString *)identifier;
{
    return [[_inspectors firstObject] inspectorIdentifier];
}

- (BOOL)hasFirstFrame;
{
    return [[_inspectors firstObject] window] != nil;
}

- (NSPoint)topLeftPoint;
{
    NSRect frameRect = [self firstFrame];
    return NSMakePoint(NSMinX(frameRect), NSMaxY(frameRect));
}

- (NSRect)firstFrame;
{
    NSWindow *window = [[_inspectors firstObject] window];
    OBASSERT(window);

    return window ? [window frame] : NSZeroRect;
}

- (void)screensDidChange:(NSNotification *)notification;
{
    if (![_inspectors count])
        return;
    
    NSRect groupRect;
    if (![self getGroupFrame:&groupRect])
        return;
    
    NSScreen *screen = [[[_inspectors firstObject] window] screen];
    
    if (screen == nil) 
        screen = [NSScreen mainScreen];
    groupRect = [self fitFrame:groupRect onScreen:screen forceVisible:YES];
    [self setTopLeftPoint:NSMakePoint(NSMinX(groupRect), NSMaxY(groupRect))];
}

- (BOOL)_frame:(NSRect)frame1 overlapsHorizontallyEnoughToConnectToFrame:(NSRect)frame2;
{
    // Return YES if either frame horizontally overlaps half or more of the other frame
    CGFloat overlap = MIN(NSMaxX(frame1), NSMaxX(frame2)) - MAX(NSMinX(frame1), NSMinX(frame2));
    return ((overlap >= (NSWidth(frame1) / 2.0)) || (overlap >= (NSWidth(frame2) / 2.0)));
}

- (BOOL)willConnectToTopOfGroup:(OIInspectorGroup *)otherGroup withFrame:(NSRect)ourFrame;
{
    NSRect otherFrame;
    
    if (![otherGroup getGroupFrame:&otherFrame])
        return NO;

    // If the bottom of our frame is not close enough to the top of the other group, return NO
    if (fabs(NSMinY(ourFrame) - NSMaxY(otherFrame)) > CONNECTION_VERTICAL_DISTANCE) {
        return NO;
    }
    return [self _frame:ourFrame overlapsHorizontallyEnoughToConnectToFrame:otherFrame];
}

- (BOOL)willConnectToBottomOfGroup:(OIInspectorGroup *)otherGroup withFrame:(NSRect)ourFrame;
{
    NSRect otherFrame;
    
    if (![otherGroup getGroupFrame:&otherFrame])
        return NO;
    
    // If the top of our frame is not close enough to the bottom of the other group, return NO
    if (fabs(NSMinY(otherFrame) - NSMaxY(ourFrame)) > CONNECTION_VERTICAL_DISTANCE) {
        return NO;
    }
    return [self _frame:ourFrame overlapsHorizontallyEnoughToConnectToFrame:otherFrame];
}

- (void)connectToBottomOfGroup:(OIInspectorGroup *)otherGroup;
{
    OBRetainAutorelease(self); // Make sure we don't get deallocated during this.

    [self disconnectWindows];
    [otherGroup disconnectWindows];
    
    for (OIInspectorController *inspector in _inspectors)
        [otherGroup addInspector:inspector];
    
    [_inspectors removeAllObjects];
    [self.inspectorRegistry removeExistingGroup:self];
    [otherGroup connectWindows];
}

#define INSERTION_CLOSENESS (12.0f)

- (BOOL)willInsertInGroup:(OIInspectorGroup *)otherGroup withFrame:(NSRect)aFrame index:(NSUInteger *)anIndex position:(CGFloat *)aPosition;
{
    NSRect groupFrame;
    CGFloat insertionPosition;
    CGFloat inspectorBreakpoint;
    
    if (![self getGroupFrame:&groupFrame])
        return NO;
    
    if (NSMinX(aFrame) + NSWidth(aFrame)/3 > NSMaxX(groupFrame) - NSWidth(aFrame)/3 || NSMaxX(aFrame) - NSWidth(aFrame)/3 < NSMinX(groupFrame) + NSWidth(groupFrame)/3)
        return NO;
    
    insertionPosition = NSMaxY(aFrame) - (OIInspectorStartingHeaderButtonHeight / 2);
    
    inspectorBreakpoint = NSMaxY(groupFrame) - NSHeight([[[_inspectors firstObject] window] frame]);
    NSUInteger index, count = [_inspectors count];
    for (index = 1; index < count; index++) {
        if (ABS(inspectorBreakpoint - insertionPosition) <= INSERTION_CLOSENESS) {
            if (anIndex)
                *anIndex = index;
            if (aPosition)
                *aPosition = inspectorBreakpoint;
            return YES;
        }
        inspectorBreakpoint -= NSHeight([[_inspectors[index] window] frame]);
    }    
    return NO;    
}

- (BOOL)insertGroup:(OIInspectorGroup *)otherGroup withFrame:(NSRect)aFrame;
{
    NSArray *insertions;
    NSArray *below;
    NSUInteger index, count;
    
    if (![self willInsertInGroup:otherGroup withFrame:aFrame index:&index position:NULL])
        return NO;
        
    [self disconnectWindows];
    [otherGroup disconnectWindows];
    
    OBRetainAutorelease(otherGroup); // remove below could be the last reference
    [self.inspectorRegistry removeExistingGroup:otherGroup];
    
    count = [_inspectors count];
    insertions = [otherGroup inspectors];
    below = [_inspectors subarrayWithRange:NSMakeRange(index, count - index)];
            
    [_inspectors removeObjectsInRange:NSMakeRange(index, count - index)];
            
    count = [insertions count];
    for (index = 0; index < count; index++)
        [self addInspector:[insertions objectAtIndex:index]];
    count = [below count];
    for (index = 0; index < count; index++)
        [self addInspector:[below objectAtIndex:index]]; 
                
    [self connectWindows];
    return YES;
}

- (void)saveInspectorOrder;
{
    NSArray *identifiers = [_inspectors arrayByPerformingBlock:^(OIInspectorController *inspector){
        return inspector.inspectorIdentifier;
    }];

    OIWorkspace *sharedWorkspace = [OIWorkspace sharedWorkspace];
    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceWillChangeNotification object:self];

    [sharedWorkspace setInspectorGroupOrder:identifiers forIdentifier:[self identifier]];

    // Don't call -topLeftPoint when we don't have a window (i.e., we have never been shown).  Instead, just use whatever is in the plist already.  Otherwise, we'll send -frame to a nil window!
    if ([self hasFirstFrame])
        [sharedWorkspace setInspectorGroupPosition:[self topLeftPoint] forIdentifier:[self identifier]];
        
    [sharedWorkspace setInspectorGroupVisible:[self isVisible] forIdentifier:[self identifier]];

    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceDidChangeNotification object:self];
}

- (void)restoreFromIdentifier:(NSString *)restoreIdentifier withInspectors:(NSMutableDictionary *)inspectorsById;
{
    OIWorkspace *sharedWorkspace = [OIWorkspace sharedWorkspace];
    NSArray *identifiers = [sharedWorkspace inspectorGroupOrderForIdentifier:restoreIdentifier];
    BOOL willBeVisible = [sharedWorkspace inspectorGroupVisibleForIdentifier: restoreIdentifier];
    
    NSUInteger index, count = [identifiers count];
    for (index = 0; index < count; index++) {
        NSString *identifier = [identifiers objectAtIndex:index];
        OIInspectorController *controller = [inspectorsById objectForKey:identifier];

        // The controller might not have a window yet if its never been displayed.  On the other hand, we might be switching workspaces, so we can't assume it doesn't have a window.
        NSWindow *window = [controller window];

        if (controller == nil) // new version of program with inspector names changed
            continue;

        if (!willBeVisible) {
            OBASSERT([window isReleasedWhenClosed] == NO);
            [window close];
        }
        [inspectorsById removeObjectForKey:identifier];
        [self addInspector:controller];
        if (!index) {
            NSPoint position = [sharedWorkspace inspectorGroupPositionForIdentifier:identifier];
            if (CGPointEqualToPoint(position, NSZeroPoint) == NO)
                [window setFrameTopLeftPoint:position];
        }
    }
    if (![_inspectors count]) {
        OBRetainAutorelease(self); // don't deallocate ourselves here if we get removed.
        [self.inspectorRegistry removeExistingGroup:self];
        return;
    }
    
    if (willBeVisible) {
        OIInspectorRegistry *registry = [OIInspectorRegistry inspectorRegistryForMainWindow];
        if (registry.applicationDidFinishRestoringWindows)
            [self _showGroup];
        else
            [registry addGroupToShowAfterWindowRestoration:self];
    } else
        [self _hideGroup];
    
    [self setInitialBottommostInspector];
}

- (void)setInitialBottommostInspector;
{
    _inspectorGroupFlags.ignoreResizing = YES;
    [[_inspectors lastObject] setBottommostInGroup:YES];
    _inspectorGroupFlags.ignoreResizing = NO;
}

- (NSRect)calculateForInspector:(OIInspectorController *)aController willResizeToFrame:(NSRect)aFrame moveOthers:(BOOL)moveOthers;
{
    if (_inspectorGroupFlags.ignoreResizing)
        return aFrame;

    NSWindow *firstWindow = [[_inspectors firstObject] window];
    NSRect firstWindowFrame = [firstWindow frame];
    NSRect returnValue = aFrame;
    NSPoint topLeft;
    

    topLeft.x = NSMinX(firstWindowFrame);
    topLeft.y = NSMaxY(firstWindowFrame);
    
    // Set positions of all panes

    _inspectorGroupFlags.ignoreResizing = YES;
    
    for (OIInspectorController *controller in _inspectors) {
        if (controller == aController) {
            returnValue.origin.x = topLeft.x;
            returnValue.origin.y = topLeft.y - returnValue.size.height;
            topLeft.y -= returnValue.size.height;
        } else {
            CGFloat height = [controller heightAfterTakeNewPosition];
            [controller setNewPosition:topLeft];
            topLeft.y -= height;
            if (moveOthers) 
                [controller takeNewPositionWithWidth:aFrame.size.width];
        }
    }
    _inspectorGroupFlags.ignoreResizing = NO;
    return returnValue;
}

- (void)controllerWindowDidResize:(NSNotification *)notification;
{
    NSWindow *window = [notification object];
 
    OIInspectorController *foundController = nil;
    for (OIInspectorController *possibleController in _inspectors)
        if ([possibleController window] == window) {
            foundController = possibleController;
            break;
        }

    OBASSERT(foundController);
    if (foundController)
        [self calculateForInspector:foundController willResizeToFrame:[window frame] moveOthers:YES];
}

#define OVERLAP_ALLOWANCE (10.0f)

- (CGFloat)yPositionOfGroupBelowWithSingleHeight:(CGFloat)singleControllerHeight;
{
    NSRect firstFrame = [self firstFrame];
    NSUInteger index = [self.inspectorRegistry.existingGroups count];
    CGFloat result = NSMinY([[[[_inspectors firstObject] window] screen] visibleFrame]);
    CGFloat ignoreAbove = (NSMaxY(firstFrame) - ((CGFloat)([_inspectors count] - 1) * OIInspectorStartingHeaderButtonHeight) - singleControllerHeight);
    
    while (index--) {
        OIInspectorGroup *group = [self.inspectorRegistry.existingGroups objectAtIndex:index];
        NSRect otherFirstFrame;
        
        if (group == self || ![group isVisible])
            continue;
            
        otherFirstFrame = [group firstFrame];        
        if (NSMaxY(otherFirstFrame) > ignoreAbove) // above us
            continue;

        if ((NSMaxX(firstFrame) - OVERLAP_ALLOWANCE) < NSMinX(otherFirstFrame) || (NSMinX(firstFrame) + OVERLAP_ALLOWANCE) > NSMaxX(otherFirstFrame)) // non overlapping
            continue;        
        
        if (NSMaxY(otherFirstFrame) > result)
            result = NSMaxY(otherFirstFrame);
    }
    return result;
}

static NSComparisonResult sortByGroupAndDisplayOrder(OIInspectorController *a, OIInspectorController *b, void *context)
{
    OIInspector *aInspector = [a inspector];
    OIInspector *bInspector = [b inspector];
    NSUInteger aOrder, bOrder;
    
    aOrder = [aInspector deprecatedDefaultDisplayGroupNumber];
    bOrder = [bInspector deprecatedDefaultDisplayGroupNumber];
    
    if (aOrder < bOrder)
        return NSOrderedAscending;
    else if (aOrder > bOrder)
        return NSOrderedDescending;
    
    aOrder = [aInspector defaultOrderingWithinGroup];
    bOrder = [bInspector defaultOrderingWithinGroup];
    
    if (aOrder < bOrder)
        return NSOrderedAscending;
    else if (aOrder > bOrder)
        return NSOrderedDescending;
    else
        return NSOrderedSame;
}

// extern MenuRef _NSGetCarbonMenu(NSMenu *);  // no longer needed

+ (void)updateMenuForControllers:(NSArray *)controllers;
{
    NSUInteger index, count, itemIndex;
    NSUInteger lastGroupIdentifier;
    NSBundle *bundle = [OIInspectorGroup bundle];
        
    // Both the controllers and the dynamic menus need to be set up before this should be called.  See -[OIDynamicInspectorMenuItem awakeFromNib] and -[OIInspectorRegistry _awakeAtLaunch].  The ordering of these two methods is indeterminate so both will provoke this method and the last one will actually cause us to do the work.
    if (!dynamicMenu || !controllers)
        return;
    
    while (dynamicMenuItemCount--)
        [dynamicMenu removeItemAtIndex:dynamicMenuItemIndex];
    itemIndex = dynamicMenuItemIndex;

    if (useWorkspaces && !useASeparateMenuForWorkspaces) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Workspace", @"OmniInspector", bundle, @"Workspace submenu item") action:NULL keyEquivalent:@""];
        [item setSubmenu:[[OIInspectorRegistry inspectorRegistryForMainWindow] workspaceMenu]];
        [dynamicMenu insertItem:item atIndex:itemIndex++];
        
    } else if (![[OIInspectorRegistry inspectorRegistryForMainWindow] hasSingleInspector]) {   // If we just have one inspector, don't offer an option to reset the inspectors
        NSMenuItem *resetInspectorsMenuItem = [[OIInspectorRegistry inspectorRegistryForMainWindow] resetPanelsItem];
        if (resetInspectorsMenuItem)
            [dynamicMenu insertItem:resetInspectorsMenuItem atIndex:itemIndex++];
    }
    
    // If there are menu items above us in the menu, insert a separator item between them and the inspector menu items we're about to insert
    if (itemIndex != 0) {
        [dynamicMenu insertItem:[NSMenuItem separatorItem] atIndex:itemIndex++];
    }
            
    controllers = [controllers sortedArrayUsingFunction:sortByGroupAndDisplayOrder context:NULL];
    count = [controllers count];
    lastGroupIdentifier = NSNotFound;
    for (index = 0; index < count; index++) {
        OIInspectorController *controller = [controllers objectAtIndex:index];

        // If we are starting a new inspector group (this inspector has a different default display group number than the last group we were working on), and the last group we processed had more than one inspector in it, add a separator item.
        unsigned int thisGroupIdentifier = [[controller inspector] deprecatedDefaultDisplayGroupNumber];
        if (thisGroupIdentifier != lastGroupIdentifier) {
            if (lastGroupIdentifier != NSNotFound)
                [dynamicMenu insertItem:[NSMenuItem separatorItem] atIndex:itemIndex++];
            lastGroupIdentifier = NSNotFound;
        } 

        NSArray *items = [[controller inspector] menuItemsForTarget:nil action:@selector(revealEmbeddedInspectorFromMenuItem:)];
        
        NSUInteger controllerItemCount = [items count], controllerItemIndex;
        for (controllerItemIndex = 0; controllerItemIndex < controllerItemCount; controllerItemIndex ++) {
            [dynamicMenu insertItem:[items objectAtIndex:controllerItemIndex] atIndex:itemIndex++];
            lastGroupIdentifier = thisGroupIdentifier;
        }
    }
        
    dynamicMenuItemCount = itemIndex - dynamicMenuItemIndex;
}

@end
