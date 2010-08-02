// Copyright 2002-2007, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIInspectorGroup.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/NSWindow-OAExtensions.h>
#import <OmniAppKit/OAColorWell.h>

#import "OIInspectorController.h"
#import "OIInspectorRegistry.h"
#import "OIInspector.h"

RCS_ID("$Id$");

@interface OIInspectorGroup (/*Private*/)
- (void)_showGroup;
- (void)_hideGroup;
- (void)disconnectWindows;
- (void)connectWindows;
- (NSString *)identifier;
- (NSPoint)topLeftPoint;
- (NSRect)firstFrame;
- (void)screensDidChange:(NSNotification *)notification;
- (BOOL)_frame:(NSRect)frame1 overlapsHorizontallyEnoughToConnectToFrame:(NSRect)frame2;
- (BOOL)willConnectToBottomOfGroup:(OIInspectorGroup *)otherGroup withFrame:(NSRect)aFrame;
- (BOOL)willConnectToTopOfGroup:(OIInspectorGroup *)otherGroup withFrame:(NSRect)aFrame;
- (void)connectToBottomOfGroup:(OIInspectorGroup *)otherGroup;
- (BOOL)willInsertInGroup:(OIInspectorGroup *)otherGroup withFrame:(NSRect)aRect index:(NSUInteger *)anIndex position:(CGFloat *)aPosition;
- (BOOL)insertGroup:(OIInspectorGroup *)otherGroup withFrame:(NSRect)aFrame;
- (void)saveInspectorOrder;
- (void)restoreFromIdentifier:(NSString *)identifier withInspectors:(NSMutableDictionary *)inspectors;
- (void)setInitialBottommostInspector;
- (NSRect)calculateForInspector:(OIInspectorController *)aController willResizeToFrame:(NSRect)aFrame moveOthers:(BOOL)moveOthers;
- (void)controllerWindowDidResize:(NSNotification *)notification;
- (CGFloat)yPositionOfGroupBelowWithSingleHeight:(CGFloat)singleControllerHeight;
+ (void)updateMenuForControllers:(NSArray *)controllers;
@end

@implementation OIInspectorGroup

#define CONNECTION_DISTANCE_SQUARED 225.0
#define CONNECTION_VERTICAL_DISTANCE	(5.0)
#define ANIMATION_VERTICAL_DISTANCE	(30.0)

static NSMutableArray *existingGroups;
static NSMenu *dynamicMenu;
static NSUInteger dynamicMenuItemIndex;
static NSUInteger dynamicMenuItemCount;
static BOOL useWorkspaces = NO;
static BOOL useASeparateMenuForWorkspaces = NO;

+ (void)initialize;
{
    OBINITIALIZE;
    existingGroups = [[NSMutableArray alloc] init];
}

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

+ (void)saveExistingGroups;
{
    NSMutableArray *identifiers = [NSMutableArray array];
    
    for (OIInspectorGroup *group in existingGroups) {
        [group saveInspectorOrder];
        [identifiers addObject:[group identifier]];
    }

    [[[OIInspectorRegistry sharedInspector] workspaceDefaults] setObject:identifiers forKey:@"_groups"];
    [[OIInspectorRegistry sharedInspector] defaultsDidChange];
}


static NSComparisonResult sortGroupByGroupNumber(OIInspectorGroup *a, OIInspectorGroup *b, void *context)
{
    int aOrder = [[[[a inspectors] objectAtIndex:0] inspector] deprecatedDefaultDisplayGroupNumber];
    int bOrder = [[[[b inspectors] objectAtIndex:0] inspector] deprecatedDefaultDisplayGroupNumber];

    if (aOrder < bOrder)
        return NSOrderedAscending;
    else if (aOrder > bOrder)
        return NSOrderedDescending;
    else
        return NSOrderedSame;
}

+ (NSWindow *)_windowInRect:(NSRect)aRect fromWindows:(NSArray *)windows;
{
    for (NSWindow *window in windows)
        if (NSIntersectsRect(aRect, [window frame]))
            return window;
    return nil;
}

#define INSPECTOR_PADDING OIInspectorStartingHeaderButtonHeight
+ (void)restoreInspectorGroupsWithInspectors:(NSArray *)inspectorList;
{
    NSArray *groups = [[[[[OIInspectorRegistry sharedInspector] workspaceDefaults] objectForKey:@"_groups"] copy] autorelease];
    NSMutableDictionary *inspectorById = [NSMutableDictionary dictionary];
    
    // Obsolete name of a method, make sure nobody's trying to override it
    OBASSERT(![self respondsToSelector:@selector(_adjustTopLeftDefaultPositioningPoint:)]);
    
    [self clearAllGroups];
    [self updateMenuForControllers:inspectorList];
        
    // load controllers
    for (OIInspectorController *controller in inspectorList)
        [inspectorById setObject:controller forKey:[controller identifier]];
    
    // restore existing groups from defaults
    for (NSString *identifier in groups) {
        OIInspectorGroup *group = [[OIInspectorGroup alloc] init];
        [group restoreFromIdentifier:identifier withInspectors:inspectorById];
        [group autorelease];
    }      
      
    // build new groups out of any new inspectors
    NSMutableDictionary *inspectorGroupsByNumber = [NSMutableDictionary dictionary];
    NSMutableArray *inspectorListSorted = [NSMutableArray arrayWithArray:[inspectorById allValues]];

    [inspectorListSorted sortUsingFunction:sortByDefaultDisplayOrderInGroup context:nil];
    
    for (OIInspectorController *controller in inspectorListSorted) {
        // Make sure we have our window set up for the size computations below.
        [controller loadInterface];

        NSNumber *groupKey = [NSNumber numberWithInt:[[controller inspector] deprecatedDefaultDisplayGroupNumber]];
        OIInspectorGroup *group = [inspectorGroupsByNumber objectForKey:groupKey];
        if (group == nil) {
            group = [[OIInspectorGroup alloc] init];
            [inspectorGroupsByNumber setObject:group forKey:groupKey];
            [group release];
        }
        [group addInspector:controller];
    }

    NSRect mainScreenVisibleRect = [[NSScreen mainScreen] visibleFrame];
    CGFloat screenScaleFactor = [[NSScreen mainScreen] userSpaceScaleFactor];
    NSMutableArray *inspectorColumns = [NSMutableArray array];
    [inspectorColumns addObject:[NSMutableArray array]];
    CGFloat freeVerticalSpace = NSHeight(mainScreenVisibleRect);
    CGFloat minFreeHeight = freeVerticalSpace;
    
    NSArray *groupsInOrder = [[inspectorGroupsByNumber allValues] sortedArrayUsingFunction:sortGroupByGroupNumber context:nil];

    NSUInteger groupIndex = [groupsInOrder count];
    while (groupIndex--) {
        OIInspectorGroup *group = [groupsInOrder objectAtIndex:groupIndex];
        CGFloat singlePaneExpandedMaxHeight = [group singlePaneExpandedMaxHeight];

        if (freeVerticalSpace > singlePaneExpandedMaxHeight) {
            [[inspectorColumns objectAtIndex:0] insertObject:group atIndex:0];
            freeVerticalSpace -= singlePaneExpandedMaxHeight;
            if (freeVerticalSpace < minFreeHeight)
                minFreeHeight = freeVerticalSpace;
        } else if (groupIndex > 0) {
            [inspectorColumns addObject:[NSMutableArray array]];
            freeVerticalSpace = NSHeight(mainScreenVisibleRect);
        }
    }
    
    // Determine the default inspector position
    NSPoint topLeft;
    float inspectorWidth = [[OIInspectorRegistry sharedInspector] inspectorWidth];
    NSString *defaultPositionString = [[OFPreferenceWrapper sharedPreferenceWrapper] objectForKey:@"OIInspectorDefaultTopLeftPosition"];
    // If a default position has been specified, use it
    if (defaultPositionString) {
        topLeft = NSPointFromString(defaultPositionString);
        // interpret y as a distance from the top of the screen, not from the bottom
        topLeft.y = NSMaxY(mainScreenVisibleRect) - topLeft.y;
    }
    // Otherwise, calculate the default inspector position based on the screen size
    else {
        NSString *defaultPlacementString = [[OFPreferenceWrapper sharedPreferenceWrapper] objectForKey:@"OIInspectorSideOfScreen"];
        if ([defaultPlacementString isEqualToString:@"left"]) {
            // position on the left side of the screen
            topLeft.x = screenScaleFactor * INSPECTOR_PADDING;
        } else {
            // position on the right side of the screen
            topLeft.x = NSMaxX(mainScreenVisibleRect) - screenScaleFactor * (inspectorWidth + INSPECTOR_PADDING);
        }
        topLeft.y = NSMaxY(mainScreenVisibleRect) - screenScaleFactor * MIN(INSPECTOR_PADDING, minFreeHeight);
    }
    topLeft = [[OIInspectorRegistry sharedInspector] adjustTopLeftDefaultPositioningPoint:topLeft];
    
    for (NSArray *groupsInColumn in inspectorColumns) {
        for (OIInspectorGroup *group in groupsInColumn) {
            [group setInitialBottommostInspector];
            [group setTopLeftPoint:topLeft];

            if ([group defaultGroupVisibility])
                [group showGroup];
            else
                [group hideGroup];

            topLeft.y -= screenScaleFactor * ( [group singlePaneExpandedMaxHeight] + OIInspectorStartingHeaderButtonHeight );
        }

        topLeft.x -= screenScaleFactor * ( inspectorWidth - OIInspectorColumnSpacing );
        if (topLeft.x < NSMinX(mainScreenVisibleRect)) 
            topLeft.x = NSMaxX(mainScreenVisibleRect) - screenScaleFactor * ( inspectorWidth + INSPECTOR_PADDING );

        topLeft.y = NSMaxY(mainScreenVisibleRect) - screenScaleFactor * MIN(INSPECTOR_PADDING, minFreeHeight);
    }
	
    [self forceAllGroupsToCheckScreenGeometry];
}

- (void)_removeAllInspectors;
{
    [_inspectors makeObjectsPerformSelector:@selector(setGroup:) withObject:nil];
    [_inspectors removeAllObjects];
}

+ (void)clearAllGroups;
{
    [existingGroups makeObjectsPerformSelector:@selector(hideGroup)];
    [existingGroups makeObjectsPerformSelector:@selector(_removeAllInspectors)];
    [existingGroups removeAllObjects];
}

+ (void)setDynamicMenuPlaceholder:(NSMenuItem *)placeholder;
{
    dynamicMenu = [placeholder menu];
    dynamicMenuItemIndex = [[dynamicMenu itemArray] indexOfObject:placeholder];
    dynamicMenuItemCount = 0;
    
    [dynamicMenu removeItemAtIndex:dynamicMenuItemIndex];
}

static NSComparisonResult sortGroupByWindowZOrder(OIInspectorGroup *a, OIInspectorGroup *b, void *zOrder)
{
    NSUInteger aOrder = [(NSArray *)zOrder indexOfObject:[[[a inspectors] objectAtIndex:0] window]];
    NSUInteger bOrder = [(NSArray *)zOrder indexOfObject:[[[b inspectors] objectAtIndex:0] window]];

    // opposite order as in original zOrder array
    if (aOrder > bOrder)
        return NSOrderedAscending;
    else if (aOrder < bOrder)
        return NSOrderedDescending;
    else
        return NSOrderedSame;
}

+ (NSArray *)groups;
{
    [existingGroups sortUsingFunction:sortGroupByWindowZOrder context:[NSWindow windowsInZOrder]];
    return existingGroups;
}

+ (NSUInteger)groupCount;
{
    return [existingGroups count];
}

+ (NSArray *)visibleGroups;
{
    NSMutableArray *visibleGroups = [NSMutableArray array];
    
    for (OIInspectorGroup *group in existingGroups)
        if ([group isVisible])
            [visibleGroups addObject:group];

    return visibleGroups;
}

/*"
This method iterates over the inspectors controllers in each visible inspector group to build a list of the visible inspector windows. Each inspector in an inspector group has its own window, even if the inspector is collapsed (the window draws the collapsed inspector title bar in that case) so all windows in a visible inspector group are visible and are thus included in the returned array. Callers should not rely on the order of the returned array.
"*/
+ (NSArray *)visibleWindows;
{
    NSMutableArray *windows = [NSMutableArray array];
    for (OIInspectorGroup *group in existingGroups) {
        if ([group isVisible]) {
            for (OIInspectorController *inspector in [group inspectors])
                [windows addObject:[inspector window]];
        }
    }

    return windows;
}

+ (void)forceAllGroupsToCheckScreenGeometry;
{
	[existingGroups makeObjectsPerformSelector:@selector(screensDidChange:) withObject:nil];
}

// Init and dealloc

- init;
{
    if ([super init] == nil)
        return nil;
    
    [existingGroups addObject:self];
    _inspectors = [[NSMutableArray alloc] init];
    _inspectorGroupFlags.screenChangesEnabled = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screensDidChange:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    return self;
}

- (void)dealloc;
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
    [_inspectors makeObjectsPerformSelector:@selector(setGroup:) withObject:nil];
    [_inspectors release];
    [super dealloc];
}

// API

- (BOOL)defaultGroupVisibility;
{
    for (OIInspectorController *inspector in _inspectors)
        if ([[inspector inspector] defaultVisibilityState] != OIHiddenVisibilityState)
            return YES;
    return NO;
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
    [[[_inspectors objectAtIndex:0] window] orderFront:self];
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
        _resizingInspector = [inspectorController retain];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(controllerWindowDidResize:) name:NSWindowDidResizeNotification object:[inspectorController window]];
    }
}

- (void)inspectorDidFinishResizing:(OIInspectorController *)inspectorController;
{
    if (inspectorController == _resizingInspector) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResizeNotification object:[inspectorController window]];
        [_resizingInspector release];
        _resizingInspector = nil;
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
    NSWindow *topWindow = [[_inspectors objectAtIndex:0] window];
#endif
    OIInspectorGroup *newGroup = [[[OIInspectorGroup alloc] init] autorelease];
    OBASSERT([existingGroups indexOfObjectIdenticalTo:newGroup]); // It is in this array and retained by it.
    
    NSUInteger inpectorCount = [_inspectors count];
    
    [self disconnectWindows];
    
    for (NSUInteger inspectorIndex = originalIndex; inspectorIndex < inpectorCount; inspectorIndex++) {
        OIInspectorController *controller = [_inspectors objectAtIndex:inspectorIndex];
        [newGroup addInspector:controller];
    }
    [_inspectors removeObjectsInRange:NSMakeRange(originalIndex, inpectorCount - originalIndex)];  

    [self connectWindows];
    [newGroup connectWindows];
    [[aController window] resetCursorRects]; // for the close buttons to highlight correctly in all cases
    
    OBPOSTCONDITION([_inspectors count] == originalIndex);
    OBPOSTCONDITION([[topWindow childWindows] count] == (originalIndex - 1));
}

- (BOOL)isHeadOfGroup:(OIInspectorController *)aController;
{
    return aController == [_inspectors objectAtIndex:0];
}

- (BOOL)isOnlyExpandedMemberOfGroup:(OIInspectorController *)aController;
{
    for (OIInspectorController *controller in _inspectors) {
        if (controller != aController && [controller isExpanded])
            return NO;
    }
    return YES;
}

- (NSArray *)inspectors;
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
        return [[[_inspectors objectAtIndex:0] window] isVisible];
}

- (BOOL)isBelowOverlappingGroup;
{
    NSRect groupFrame;
    if (![self getGroupFrame:&groupFrame])
        return NO;
    
    NSArray *orderedGroups = [[self class] groups];
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
    
    for (OIInspectorController *inspector in _inspectors) {
        CGFloat inspectorDesired = [inspector desiredHeightWhenExpanded];
        
        if (inspectorDesired > result)
            result = inspectorDesired;
    }
    return (result + (CGFloat)OIInspectorStartingHeaderButtonHeight * ([_inspectors count] - 1));
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
    NSWindow *topWindow = [[_inspectors objectAtIndex:0] window];
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
    for (OIInspectorGroup *otherGroup in existingGroups) {
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
    
    for (OIInspectorGroup *otherGroup in existingGroups) {
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

        count = [existingGroups count];
        for (index = 0; index < count; index++) {
            OIInspectorGroup *otherGroup = [existingGroups objectAtIndex:index];
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
    [self retain];

    for (OIInspectorGroup *otherGroup in existingGroups) {
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
    [self autorelease];
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

#pragma mark -
#pragma mark Private

- (void)_hideGroup;
{
    [self disconnectWindows];
    
    for (OIInspectorController *inspector in _inspectors) {
        OBASSERT([[inspector window] isReleasedWhenClosed] == NO);
        [[inspector window] close];
    }
}

- (void)_showGroup;
{
    NSUInteger index, count = [_inspectors count];

    _inspectorGroupFlags.isShowing = YES;

    // Remember whether there were previously any visible inspectors
    BOOL hadVisibleInspector = [[OIInspectorRegistry sharedInspector] hasVisibleInspector];
    
    // Position windows if we haven't already
    if (!_inspectorGroupFlags.hasPositionedWindows) {
        _inspectorGroupFlags.hasPositionedWindows = YES;
        
        NSDictionary *defaults = [[OIInspectorRegistry sharedInspector] workspaceDefaults];
        for (index = 0; index < count; index++) {
            OIInspectorController *controller = [_inspectors objectAtIndex:index];
            NSString *identifier = [controller identifier];

            [controller loadInterface];
            NSWindow *window = [controller window];
            OBASSERT(window);
            if (!index) {
                NSString *position = [defaults objectForKey:[NSString stringWithFormat:@"%@-Position", identifier]];
                if (position)
                    [window setFrameTopLeftPoint:NSPointFromString(position)];
            }
        }
    }

    // If there were previously no visible inspectors, update the inspection set.  We need to do this now (not queued) and even if there are no inspectors visible (since there aren't).  The issue is that the inspection set may hold pointers to objects from closed documents that are partially dead or otherwise invalid.  We want the inspectors to show the right stuff when they come on screen anyway rather than coming up and then getting updated.  We do NOT want to tell the inspectors about the updated inspection set immediately (+updateInspectionSetImmediatelyAndUnconditionally doesn't) since -prepareWindowForDisplay will do that and it would just be redundant.
    if (!hadVisibleInspector)
        [OIInspectorRegistry updateInspectionSetImmediatelyAndUnconditionally];
    
    index = count;
    while (index--) 
        [[_inspectors objectAtIndex:index] prepareWindowForDisplay];
    [self setTopLeftPoint:[self topLeftPoint]];

    // to make sure they are placed visibly and ordered correctly
    [self screensDidChange:nil];
      
    for (index = 0; index < count; index++)
        [[_inspectors objectAtIndex:index] displayWindow];
    
    [self connectWindows];
    _inspectorGroupFlags.isShowing = NO;
}

- (void)disconnectWindows;
{
    NSWindow *topWindow = [[_inspectors objectAtIndex:0] window];
    NSUInteger index = [_inspectors count];
    
    OBPRECONDITION(!topWindow || ([[topWindow childWindows] count] == index-1));
    while (index-- > 1) 
        [topWindow removeChildWindow:[[_inspectors objectAtIndex:index] window]];
        
    OBPOSTCONDITION([[topWindow childWindows] count] == 0);
}

- (void)connectWindows;
{
    NSUInteger index, count = [_inspectors count];
    NSWindow *topWindow = [[_inspectors objectAtIndex:0] window];
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
    return [[_inspectors objectAtIndex:0] identifier];
}

- (BOOL)hasFirstFrame;
{
    return [[_inspectors objectAtIndex:0] window] != nil;
}

- (NSPoint)topLeftPoint;
{
    NSRect frameRect = [self firstFrame];
    return NSMakePoint(NSMinX(frameRect), NSMaxY(frameRect));
}

- (NSRect)firstFrame;
{
    NSWindow *window = [[_inspectors objectAtIndex:0] window];
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
    
    NSScreen *screen = [[[_inspectors objectAtIndex:0] window] screen];
    
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
    [self retain];
    [self disconnectWindows];
    [otherGroup disconnectWindows];
    
    for (OIInspectorController *inspector in _inspectors)
        [otherGroup addInspector:inspector];
    
    [_inspectors removeAllObjects];
    [existingGroups removeObject:self];
    [otherGroup connectWindows];
    [self autorelease];
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
    
    inspectorBreakpoint = NSMaxY(groupFrame) - NSHeight([[[_inspectors objectAtIndex:0] window] frame]);
    NSUInteger index, count = [_inspectors count];
    for (index = 1; index < count; index++) {
        if (ABS(inspectorBreakpoint - insertionPosition) <= INSERTION_CLOSENESS) {
            if (anIndex)
                *anIndex = index;
            if (aPosition)
                *aPosition = inspectorBreakpoint;
            return YES;
        }
        inspectorBreakpoint -= NSHeight([[[_inspectors objectAtIndex:index] window] frame]);
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
    
    [[otherGroup retain] autorelease]; // remove below could be the last reference
    [existingGroups removeObject:otherGroup];
    
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
    NSArray *identifiers = [_inspectors valueForKey:@"identifier"];
    NSMutableDictionary *defaults = [[OIInspectorRegistry sharedInspector] workspaceDefaults];
    [defaults setObject:identifiers forKey:[NSString stringWithFormat:@"%@-Order", [self identifier]]];
    
    // Don't call -topLeftPoint when we don't have a window (i.e., we have never been shown).  Instead, just use whatever is in the plist already.  Otherwise, we'll send -frame to a nil window!
    if ([self hasFirstFrame])
	[defaults setObject:NSStringFromPoint([self topLeftPoint]) forKey:[NSString stringWithFormat:@"%@-Position", [self identifier]]];
    
    NSString *visibleKey = [NSString stringWithFormat:@"%@-Visible", [self identifier]];
    if ([self isVisible])
        [defaults setObject:@"YES" forKey:visibleKey];
    else
        [defaults removeObjectForKey:visibleKey];
}

- (void)restoreFromIdentifier:(NSString *)identifier withInspectors:(NSMutableDictionary *)inspectorsById;
{
    NSDictionary *defaults = [[OIInspectorRegistry sharedInspector] workspaceDefaults];
    NSArray *identifiers = [defaults objectForKey:[NSString stringWithFormat:@"%@-Order", identifier]];
    BOOL willBeVisible = [defaults objectForKey:[NSString stringWithFormat:@"%@-Visible", identifier]] != nil;
    
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
            NSString *position = [defaults objectForKey:[NSString stringWithFormat:@"%@-Position", identifier]];
            if (position)
                [window setFrameTopLeftPoint:NSPointFromString(position)];
        }
    }
    if (![_inspectors count]) {
        [[self retain] autorelease]; // don't deallocate ourselves here if we get removed.
        [existingGroups removeObject:self];
        return;
    }
    
    [self setInitialBottommostInspector];
    
    if (willBeVisible) 
        [self _showGroup];
    else
        [self _hideGroup];
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

    NSWindow *firstWindow = [[_inspectors objectAtIndex:0] window];
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
    NSUInteger index = [existingGroups count];
    CGFloat result = NSMinY([[[[_inspectors objectAtIndex:0] window] screen] visibleFrame]);
    CGFloat ignoreAbove = (NSMaxY(firstFrame) - ((CGFloat)([_inspectors count] - 1) * OIInspectorStartingHeaderButtonHeight) - singleControllerHeight);
    
    while (index--) {
        OIInspectorGroup *group = [existingGroups objectAtIndex:index];
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
    NSMenuItem *item;
    NSBundle *bundle = [OIInspectorGroup bundle];
        
    // Both the controllers and the dynamic menus need to be set up before this should be called.  See -[OIDynamicInspectorMenuItem awakeFromNib] and -[OIInspectorRegistry _awakeAtLaunch].  The ordering of these two methods is indeterminate so both will provoke this method and the last one will actually cause us to do the work.
    if (!dynamicMenu || ![controllers count])
        return;
    
    while (dynamicMenuItemCount--)
        [dynamicMenu removeItemAtIndex:dynamicMenuItemIndex];
    itemIndex = dynamicMenuItemIndex;

    if (useWorkspaces && !useASeparateMenuForWorkspaces) {
        item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Workspace", @"OmniInspector", bundle, @"Workspace submenu item") action:NULL keyEquivalent:@""] autorelease];
        [item setSubmenu:[[OIInspectorRegistry sharedInspector] workspaceMenu]];
    } else {
        item = [[OIInspectorRegistry sharedInspector] resetPanelsItem];
    }
    [dynamicMenu insertItem:item atIndex:itemIndex++];
    [dynamicMenu insertItem:[NSMenuItem separatorItem] atIndex:itemIndex++];
            
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

        NSArray *items = [[controller inspector] menuItemsForTarget:controller action:@selector(toggleVisibleAction:)];
        
        NSUInteger controllerItemCount = [items count], controllerItemIndex;
        for (controllerItemIndex = 0; controllerItemIndex < controllerItemCount; controllerItemIndex ++) {
            [dynamicMenu insertItem:[items objectAtIndex:controllerItemIndex] atIndex:itemIndex++];
            lastGroupIdentifier = thisGroupIdentifier;
        }
    }
        
    dynamicMenuItemCount = itemIndex - dynamicMenuItemIndex;
}

@end
