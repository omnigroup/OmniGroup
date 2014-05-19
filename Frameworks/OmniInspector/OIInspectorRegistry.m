// Copyright 2002-2008, 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIInspectorRegistry.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/NSBundle-OAExtensions.h>
#import <OmniAppKit/NSWindow-OAExtensions.h>
#import <OmniAppKit/OAApplication.h>
#import <OmniAppKit/OAWindowCascade.h>
#import <OmniAppKit/OAVersion.h>

#import "OIInspectableControllerProtocol.h"
#import "OIInspectionSet.h"
#import "OIInspector.h"
#import "OIInspectorController.h"
#import "OIInspectorGroup-Internal.h"
#import "OITabbedInspector.h"


#import "OIInspectionSet.h"

RCS_ID("$Id$");

@interface OIInspectorRegistry () <NSTableViewDelegate>

@property(readwrite,assign) Class defaultInspectorControllerClass;

@property (strong, nonatomic) IBOutlet NSPanel *saveWorkspacePanel, *editWorkspacePanel;
@property (strong, nonatomic) IBOutlet NSTextField *makeWorkspaceTextField;
@property (strong, nonatomic) IBOutlet NSButtonCell *deleteWorkspaceButton;
@property (strong, nonatomic) IBOutlet NSButton *restoreWorkspaceButton;
@property (strong, nonatomic) IBOutlet NSButton *overwriteWorkspaceButton;
@property (strong, nonatomic) IBOutlet NSButton *workspacesHelpButton;

@end

NSString * const OIInspectionSetChangedNotification = @"OIInspectionSetChangedNotification";
NSString * const OIWorkspacesHelpURLKey = @"OIWorkspacesHelpURL";

static NSMutableArray *additionalPanels = nil;
static NSString *inspectorDefaultsVersion = nil;

@implementation OIInspectorRegistry
{
    NSWindow *lastWindowAskedToInspect;
    NSWindow *lastMainWindowBeforeAppSwitch;
    
    OIInspectionSet *inspectionSet;
    
    NSMenu *workspaceMenu;
    NSTimer *configurationsChangedTimer;
    
    struct {
	unsigned int isInspectionQueued:1;
	unsigned int isListeningForNotifications:1;
	unsigned int isInvalidated:1;
    } registryFlags;
    
    NSMutableArray *inspectorControllers;
    float inspectorWidth;
    NSString *_currentInspectionIdentifier;
    
    BOOL _applicationDidFinishRestoringWindows;	// for document based app on 10.7, this means that the app has loaded its documents
    NSMutableArray *_groupsToShowAfterWindowRestoration;
}

+ (void)initialize;
{
    OBINITIALIZE;
    additionalPanels = [[NSMutableArray alloc] init];
}

- (void)invalidate;
{
    registryFlags.isInvalidated = YES;
}

- (void)dealloc;
{
    if (registryFlags.isListeningForNotifications) {
        registryFlags.isListeningForNotifications = NO;
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

+ (void)setInspectorDefaultsVersion:(NSString *)versionString;
{
    inspectorDefaultsVersion = versionString;
}

- (OIInspectorController *)controllerWithInspector:(OIInspector *)inspector;
{
    // This method is here so that it can be overridden by app-specific subclasses of OIInspectorRegistry
    OIInspectorController *controller = [[self.defaultInspectorControllerClass alloc] initWithInspector:inspector];
    controller.inspectorRegistry = self;
    return controller;
}

+ (void)registerAdditionalPanel:(NSWindowController *)additionalController;
{
    [additionalPanels addObject:additionalController];
}

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(id)descriptionDictionary
{
    NSString *inspectorIdentifier = [descriptionDictionary objectForKey:@"identifier"];
    if(![descriptionDictionary isKindOfClass:[NSDictionary class]] || ![itemName isEqualToString:inspectorIdentifier]) {
        NSLog(@"%@: Item %@ in %@ is not a registerable inspector", NSStringFromClass(self), itemName, bundle);
        return;
    }
    
    // NSLog(@"%@: registering %@ from %@", NSStringFromClass(self), itemName, bundle);
    
    OIInspectorRegistry *registry = [OIInspectorRegistry inspectorRegistryForMainWindow]; // Make sure the class has woken up
    
    if ([registry controllerWithIdentifier:inspectorIdentifier] != nil) {
        NSLog(@"Ignoring duplicate inspector %@ from %@", inspectorIdentifier, bundle);
        return;
    }
    
    NSString *groupIdentifier = [descriptionDictionary objectForKey:@"group"];
    if (groupIdentifier) {
        OIInspectorController *groupController = [registry controllerWithIdentifier:groupIdentifier];
        OIInspector *parent = [groupController inspector];
        if (groupController == nil || ![parent isKindOfClass:[OITabbedInspector class]]) {
            NSLog(@"Inspector %@ from %@ specifies unknown tab group %@ (discarding)", inspectorIdentifier, bundle, groupIdentifier);
        }
        [(OITabbedInspector *)parent registerInspectorDictionary:descriptionDictionary inspectorRegistry:registry bundle:bundle];
    } else {
        OIInspector *inspector = [OIInspector newInspectorWithDictionary:descriptionDictionary inspectorRegistry:registry bundle:bundle];
        [registry _registerInspector:inspector];
    }
}

+ (BOOL)allowsEmptyInspectorList;
{
    // By default, applications which link against OmniInspector out of necessity can opt-out by including an empty "OIInspectors" list in its Info.plist.
    //
    // An application which uses OmniInspector, but has an empty inspector list (e.g. OmniGraffle) should override this to return YES.
    
    return NO;
}

+ (OIInspectorRegistry *)inspectorRegistryForMainWindow;
{
#ifdef DEBUG_tom0
#error The main window may know nothing about inspectors. For example, if the main window is a software update window, it should not be consulted. <bug:///99522> (Silent crash in software update)
#endif
    return [[NSApp delegate] inspectorRegistryForWindow:[NSApp mainWindow]];
}

static NSMutableArray *hiddenGroups = nil;
static NSMutableArray *hiddenPanels = nil;
    
- (void)tabShowHidePanels;
{
    NSMutableArray *visibleGroups = [NSMutableArray array];
    NSMutableArray *visiblePanels = [NSMutableArray array];
    
    for (OIInspectorGroup *group in self.existingGroups) {
        if ([group isVisible]) {
            [visibleGroups addObject:group];
            [group hideGroup];
        }
    }
    
    for (NSWindowController *controller in additionalPanels) {
        if ([[controller window] isVisible]) {
            [visiblePanels addObject:[controller window]];
            OBASSERT([[controller window] isReleasedWhenClosed] == NO);
            [[controller window] close];
        }
    }
    
    if ([visibleGroups count] || [visiblePanels count]) {
        hiddenGroups = visibleGroups;
        hiddenPanels = visiblePanels;
    } else if ([hiddenGroups count] || [hiddenPanels count]) {
        [hiddenGroups makeObjectsPerformSelector:@selector(showGroup)];
        hiddenGroups = nil;
        [hiddenPanels makeObjectsPerformSelector:@selector(orderFront:) withObject:self];
        hiddenPanels = nil;
    } else {
        [self.existingGroups makeObjectsPerformSelector:@selector(showGroup)];
        
        for (NSWindowController *controller in additionalPanels)
            [[controller window] orderFront:self];
    }
}

/*" Shows all the registered inspectors.  Returns YES if any additional inspectors become visible. "*/
- (BOOL)showAllInspectors;
{
    BOOL shownAny = NO;
    
    for (OIInspectorGroup *group in [self groups])
        if (![group isVisible]) {
            shownAny = YES;
            [group showGroup];
        }
    
    [hiddenGroups removeAllObjects];
    return shownAny;
}

/*" Hides all the registered inspectors.  Returns YES if any additional inspectors become hidden. "*/
- (BOOL)hideAllInspectors;
{
    BOOL hiddenAny = NO;

    for (OIInspectorGroup *group in [self groups]) {
        if ([group isVisible]) {
            hiddenAny = YES;
            [group hideGroup];
            [hiddenGroups addObject:group];
        }
    }

    return hiddenAny;
}

- (void)toggleAllInspectors;
{
    if (![self showAllInspectors])
        [self hideAllInspectors];
}

+ (void)updateInspectorForWindow:(NSWindow *)window;
{
    OIInspectorRegistry *inspectorRegistry = [[NSApp delegate] inspectorRegistryForWindow:window];
    [inspectorRegistry updateInspectorForWindow:[NSApp mainWindow]];
}

+ (void)updateInspectionSetImmediatelyAndUnconditionallyForWindow:(NSWindow *)window;
{
    OIInspectorRegistry *inspectorRegistry = [[NSApp delegate] inspectorRegistryForWindow:window];
    [inspectorRegistry updateInspectionSetImmediatelyAndUnconditionallyForWindow:window];
}

+ (void)clearInspectionSetForWindow:(NSWindow *)window;
{
    OIInspectorRegistry *inspectorRegistry = [[NSApp delegate] inspectorRegistryForWindow:window];
    [inspectorRegistry clearInspectionSet];
}

- (void)updateInspectorForWindow:(NSWindow *)window;
{
    [self _inspectWindow:window queue:YES onlyIfVisible:YES updateInspectors:YES];
}

- (void)updateInspectionSetImmediatelyAndUnconditionallyForWindow:(NSWindow *)window;
{
    [self _inspectWindow:window queue:NO onlyIfVisible:NO updateInspectors:NO];
}

- (void)clearInspectionSet;
{
    [[self inspectionSet] removeAllObjects];
    [self _postInspectionSetChangedNotificationAndUpdateInspectors:YES];
}

- (OIInspectorController *)controllerWithIdentifier:(NSString *)anIdentifier;
{
    OFForEachInArray(inspectorControllers, OIInspectorController *, anInspector, {
        if ([[anInspector identifier] isEqualToString:anIdentifier])
            return anInspector;
    });
    
    return nil;
}

- (NSArray *)controllers;
{
    return [inspectorControllers copy];
}

- (void)removeInspectorController:(OIInspectorController *)controller;
{
    // Called by OmniGraffle's subclass
    [inspectorControllers removeObjectIdenticalTo:controller];
}

- (BOOL)hasSingleInspector;
{
    return ([inspectorControllers count] == 1);
}

- (BOOL)hasVisibleInspector;
/*" Returns YES if any of the registered inspectors are on screen and expanded. "*/
{
    for (OIInspectorController *controller in inspectorControllers) {
        // We use the -containerView here instead of just -window to cover the embedded-inspector case.
        if ([[[controller containerView] window] isVisible] && [controller isExpanded]) {
            return YES;
        }
    }
    return NO;
}

- (void)forceInspectorsVisible:(NSSet *)preferred;
{
    if (!preferred)
        return;
    
    for (OIInspectorController *controller in inspectorControllers) {
        OIInspector *panel = [controller inspector];
        if ([panel isKindOfClass:[OITabbedInspector class]]) {
            OITabbedInspector *inspectorGroup = (OITabbedInspector *)panel;
            NSMutableArray *selectedInspectors = [NSMutableArray array];
            for (NSString *identifier in [inspectorGroup tabIdentifiers])
                if ([preferred containsObject:identifier])
                    [selectedInspectors addObject:identifier];

            if ([selectedInspectors count]) {
                [inspectorGroup setSelectedTabIdentifiers:selectedInspectors pinnedTabIdentifiers:nil];
                [controller showInspector];
            }
        } else if ([preferred containsObject:[panel identifier]]) {
            [controller showInspector];
        }
    }
    
    if ([preferred containsObject:@"Font"])
        [[NSFontPanel sharedFontPanel] orderFront:nil];
}

// Init

- (NSString *)inspectorPreference;
{
    if (inspectorDefaultsVersion)
        return [@"Inspector" stringByAppendingString:inspectorDefaultsVersion];
    else
        return @"Inspector";
}

- (NSString *)inspectorWorkspacesPreference;
{
    if (inspectorDefaultsVersion)
        return [@"InspectorWorkspaces" stringByAppendingString:inspectorDefaultsVersion];
    else
        return @"InspectorWorkspaces";
}

- (id)initWithDefaultInspectorControllerClass:(Class)controllerClass;
{
    self = [super init];
    if (!self)
        return nil;
    
    OBASSERT(controllerClass == [OIInspectorController class] || [controllerClass isSubclassOfClass:[OIInspectorController class]]);
    
    self.defaultInspectorControllerClass = controllerClass;
    
    _applicationDidFinishRestoringWindows = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationDidFinishRestoringWindowsNotification:) name:NSApplicationDidFinishRestoringWindowsNotification object:nil];
    
    inspectorControllers = [[NSMutableArray alloc] init];

    _workspaceDefaults = [[[NSUserDefaults standardUserDefaults] objectForKey:[self inspectorPreference]] mutableCopy];
    if (!_workspaceDefaults)
        _workspaceDefaults = [[NSMutableDictionary alloc] init];
    _workspaces = [[[NSUserDefaults standardUserDefaults] objectForKey:[self inspectorWorkspacesPreference]] mutableCopy];
    if (!_workspaces)
        _workspaces = [[NSMutableArray alloc] init];

    _existingGroups = [[NSMutableArray alloc] init];
    
    // All the inspectors in the app will have exactly the same width.  Schemes were the inspectors change size based on which ones are expanded are really annoying since you have to allocate width on your screen for the placement of the inspectors for the worst case width anyway.  Also, it requires a bunch of crazy code which is fragile.
    inspectorWidth = 200.0f;
    
    // Register inspectors based off an entry in the main bundle's Info.plist.  This allows the application total control over which inspectors are used (i.e., it can include inspectors from frameworks or not), what order they are in, how they are grouped, etc.
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *infoDictionary = [mainBundle infoDictionary];
    NSString *inspectorWidthString = [infoDictionary objectForKey:@"OIInspectorWidth"];
    NSArray *inspectorPlists = [infoDictionary objectForKey:@"OIInspectors"];
    if (inspectorPlists == nil) {
        NSString *inspectorDictionaryPath = [mainBundle pathForResource:@"Inspectors" ofType:@"plist"];
        NSDictionary *inspectorDictionary;
        if (inspectorDictionaryPath != nil &&
            (inspectorDictionary = [NSDictionary dictionaryWithContentsOfFile:inspectorDictionaryPath]) != nil) {
            OBASSERT(inspectorWidthString == nil); // Shouldn't be specified in both places
            inspectorWidthString = [inspectorDictionary objectForKey:@"OIInspectorWidth"];
            inspectorPlists = [inspectorDictionary objectForKey:@"OIInspectors"];
        }
    } else {
        OBASSERT([mainBundle pathForResource:@"Inspectors" ofType:@"plist"] == nil);  // Catch stupid mistakes
    }
    
    if (![[self class] allowsEmptyInspectorList] && (inspectorPlists == nil || [inspectorPlists count] == 0))
        return nil;

    if (inspectorWidthString) {
        float specifiedInspectorWidth = [inspectorWidthString floatValue];
        inspectorWidth = MAX(inspectorWidth, specifiedInspectorWidth);
    }
    
    if (inspectorPlists == nil)
        NSLog(@"No OIInspectors in %@", mainBundle);
    
    unsigned inspectorOrder = 0;
    for (NSDictionary *inspectorPlist in inspectorPlists) {
        @try {
            OIInspector *inspector = [OIInspector newInspectorWithDictionary:inspectorPlist inspectorRegistry:self bundle:nil];
            [inspector setDefaultOrderingWithinGroup:inspectorOrder++];
            [self _registerInspector:inspector];
        } @catch (NSException *exc) {
            NSLog(@"Exception raised while creating inspector from plist %@: %@", [inspectorPlist objectForKey:@"class"], exc);
        }
    }
    
    OFController *appController = [OFController sharedController];
    if ([appController status] < OFControllerRunningStatus)
        [appController addObserver:self];
    else
        [self queueSelectorOnce:@selector(controllerStartedRunning:) withObject:nil];
    
    return self;
}

- (id)init;
{
    self = [self initWithDefaultInspectorControllerClass:[OIInspectorController class]];
    if (!self)
        return nil;

    return self;
}

- (NSArray *)copyObjectsInterestingToInspector:(OIInspector *)anInspector;
{
    if ([anInspector respondsToSelector:@selector(mayInspectObject:)]) {
        return [inspectionSet copyObjectsSatisfyingPredicateBlock:^BOOL(id object){
            return [anInspector mayInspectObject:object];
        }];
    } else {
        return [self copyObjectsSatisfyingPredicate:[anInspector inspectedObjectsPredicate]];
    }
}

- (NSArray *)copyObjectsSatisfyingPredicate:(NSPredicate *)predicate;
{
    return [inspectionSet copyObjectsSatisfyingPredicate:predicate];
}

- (NSArray *)inspectedObjectsOfClass:(Class)aClass;
{
    return [inspectionSet copyObjectsSatisfyingPredicate:[NSComparisonPredicate isKindOfClassPredicate:aClass]];
}

- (NSArray *)inspectedObjects;
{
    return [inspectionSet allObjects];
}

- (NSString *)inspectionIdentifierForCurrentInspectionSet;
{
    return _currentInspectionIdentifier;
}

- (OIInspectionSet *)inspectionSet;
    /*" This method allows fine tuning of the inspection.  If the inspection set is changed, -_postInspectionSetChangedNotificationAndUpdateInspectors: must be called "*/
{
    return inspectionSet;
}

- (void)resetWorkspaceDefaults;
{
    _workspaceDefaults = nil;
    [self defaultsDidChange];
}

- (void)defaultsDidChange;
{
    if (_workspaceDefaults) {
        [[NSUserDefaults standardUserDefaults] setObject:[_workspaceDefaults copy] forKey:[self inspectorPreference]];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[self inspectorPreference]];
        _workspaceDefaults = [[[NSUserDefaults standardUserDefaults] objectForKey:[self inspectorPreference]] mutableCopy];
        if (!_workspaceDefaults)
            _workspaceDefaults = [[NSMutableDictionary alloc] init];
    }
}

#pragma mark - Inspector group maintentance
- (void)saveExistingGroups;
{
    NSMutableArray *identifiers = [NSMutableArray array];
    
    for (OIInspectorGroup *group in self.existingGroups) {
        [group saveInspectorOrder];
        [identifiers addObject:[group identifier]];
    }
    
    [[[OIInspectorRegistry inspectorRegistryForMainWindow] workspaceDefaults] setObject:identifiers forKey:@"_groups"];
    [[OIInspectorRegistry inspectorRegistryForMainWindow] defaultsDidChange];
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

- (NSWindow *)_windowInRect:(NSRect)aRect fromWindows:(NSArray *)windows;
{
    for (NSWindow *window in windows)
        if (NSIntersectsRect(aRect, [window frame]))
            return window;
    return nil;
}

#define INSPECTOR_PADDING OIInspectorStartingHeaderButtonHeight
- (void)restoreInspectorGroupsWithInspectors:(NSArray *)inspectorList;
{
    @autoreleasepool {
        NSArray *groups = [[[[OIInspectorRegistry inspectorRegistryForMainWindow] workspaceDefaults] objectForKey:@"_groups"] copy];
        NSMutableDictionary *inspectorById = [NSMutableDictionary dictionary];
        
        // Obsolete name of a method, make sure nobody's trying to override it
        OBASSERT_NOT_IMPLEMENTED(self, _adjustTopLeftDefaultPositioningPoint:);
        
        [self clearAllGroups];
        [OIInspectorGroup updateMenuForControllers:inspectorList];
        
        // load controllers
        for (OIInspectorController *controller in inspectorList)
            [inspectorById setObject:controller forKey:[controller identifier]];
        
        // restore existing groups from defaults
        for (NSString *identifier in groups) {
            OIInspectorGroup *group = [[OIInspectorGroup alloc] init];
            [self.existingGroups addObject:group];
            [group restoreFromIdentifier:identifier withInspectors:inspectorById];
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
                [self.existingGroups addObject:group];
                [inspectorGroupsByNumber setObject:group forKey:groupKey];
            }
            [group addInspector:controller];
        }
        
        NSRect mainScreenVisibleRect = [[NSScreen mainScreen] visibleFrame];
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
        NSString *defaultPositionString = [[OFPreferenceWrapper sharedPreferenceWrapper] objectForKey:@"OIInspectorDefaultTopLeftPosition"];
        // If a default position has been specified, use it
        if ([defaultPositionString length]) {
            topLeft = NSPointFromString(defaultPositionString);
            // interpret y as a distance from the top of the screen, not from the bottom
            topLeft.y = NSMaxY(mainScreenVisibleRect) - topLeft.y;
        }
        // Otherwise, calculate the default inspector position based on the screen size
        else {
            NSString *defaultPlacementString = [[OFPreferenceWrapper sharedPreferenceWrapper] objectForKey:@"OIInspectorSideOfScreen"];
            if ([defaultPlacementString isEqualToString:@"left"]) {
                // position on the left side of the screen
                topLeft.x = INSPECTOR_PADDING;
            } else {
                // position on the right side of the screen
                topLeft.x = NSMaxX(mainScreenVisibleRect) - (inspectorWidth + INSPECTOR_PADDING);
            }
            topLeft.y = NSMaxY(mainScreenVisibleRect) - MIN(INSPECTOR_PADDING, minFreeHeight);
        }
        topLeft = [[OIInspectorRegistry inspectorRegistryForMainWindow] adjustTopLeftDefaultPositioningPoint:topLeft];
        
        for (NSArray *groupsInColumn in inspectorColumns) {
            for (OIInspectorGroup *group in groupsInColumn) {
                [group setInitialBottommostInspector];
                [group setTopLeftPoint:topLeft];
                
                if ([group defaultGroupVisibility] && [OIInspectorRegistry inspectorRegistryForMainWindow].applicationDidFinishRestoringWindows)
                    [group showGroup];
                else
                    [group hideGroup];
                
                topLeft.y -= ( [group singlePaneExpandedMaxHeight] + OIInspectorStartingHeaderButtonHeight );
            }
            
            topLeft.x -= ( inspectorWidth - OIInspectorColumnSpacing );
            if (topLeft.x < NSMinX(mainScreenVisibleRect))
                topLeft.x = NSMaxX(mainScreenVisibleRect) - ( inspectorWidth + INSPECTOR_PADDING );
            
            topLeft.y = NSMaxY(mainScreenVisibleRect) - MIN(INSPECTOR_PADDING, minFreeHeight);
        }
        
        [self forceAllGroupsToCheckScreenGeometry];
    }
}

- (void)clearAllGroups;
{
    [self.existingGroups makeObjectsPerformSelector:@selector(clear)];
    [self.existingGroups removeAllObjects];
}

static NSComparisonResult sortGroupByWindowZOrder(OIInspectorGroup *a, OIInspectorGroup *b, void *zOrder)
{
    OIInspectorController *inspectorA = [[a inspectors] objectAtIndex:0];
    OIInspectorController *inspectorB = [[b inspectors] objectAtIndex:0];
    
    NSUInteger aOrder = [(OB_BRIDGE NSArray *)zOrder indexOfObject:[inspectorA window]];
    NSUInteger bOrder = [(OB_BRIDGE NSArray *)zOrder indexOfObject:[inspectorB window]];
    
    // opposite order as in original zOrder array
    if (aOrder > bOrder)
        return NSOrderedAscending;
    else if (aOrder < bOrder)
        return NSOrderedDescending;
    else
        return NSOrderedSame;
}

- (NSArray *)groups;
{
    [self.existingGroups sortUsingFunction:sortGroupByWindowZOrder context:(__bridge void *)([NSWindow windowsInZOrder])];
    return self.existingGroups;
}

- (NSUInteger)groupCount;
{
    return [self.existingGroups count];
}

- (NSArray *)visibleGroups;
{
    NSMutableArray *visibleGroups = [NSMutableArray array];
    
    for (OIInspectorGroup *group in self.existingGroups)
        if ([group isVisible])
            [visibleGroups addObject:group];
    
    return visibleGroups;
}

/*"
 This method iterates over the inspectors controllers in each visible inspector group to build a list of the visible inspector windows. Each inspector in an inspector group has its own window, even if the inspector is collapsed (the window draws the collapsed inspector title bar in that case) so all windows in a visible inspector group are visible and are thus included in the returned array. Callers should not rely on the order of the returned array.
 "*/
- (NSArray *)visibleWindows;
{
    NSMutableArray *windows = [NSMutableArray array];
    for (OIInspectorGroup *group in self.existingGroups) {
        if ([group isVisible]) {
            for (OIInspectorController *inspector in [group inspectors])
                [windows addObject:[inspector window]];
        }
    }
    
    return windows;
}

- (void)forceAllGroupsToCheckScreenGeometry;
{
    [self.existingGroups makeObjectsPerformSelector:@selector(screensDidChange:) withObject:nil];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
//    if ([item action] == @selector(editWorkspace:))
//        return [_workspaces count] > 0;
    return YES;
}

- (void)_buildWorkspacesInMenu;
{
    NSInteger itemCount = [workspaceMenu numberOfItems];
    
    if ([OIInspectorGroup isUsingASeparateMenuForWorkspaces]) {
        while (itemCount-- > 1)
            [workspaceMenu removeItemAtIndex:1];
    } else {
        while (itemCount-- > 3)
            [workspaceMenu removeItemAtIndex:3];
    }

    if ([_workspaces count]) {
        unichar functionChar = NSF2FunctionKey, lastFunctionChar = NSF8FunctionKey;
        
        [workspaceMenu addItem:[NSMenuItem separatorItem]];
        
        for (NSString *title in _workspaces) {
            NSString *key = @"";
            
            if (functionChar <= lastFunctionChar) {
                key = [NSString stringWithCharacters:&functionChar length:1];
                functionChar++;
            }
            
            NSMenuItem *item = [workspaceMenu addItemWithTitle:title action:@selector(switchToWorkspace:) keyEquivalent:key];
            [item setKeyEquivalentModifierMask:0];
            [item setTarget:self];
            [item setRepresentedObject:title];
        }
    }
}

- (NSMenu *)workspaceMenu;
{
    if (!workspaceMenu) {
        NSBundle *bundle = [OIInspectorRegistry bundle];
        
        workspaceMenu = [[NSMenu alloc] initWithTitle:@"Workspace"];
        
        NSMenuItem *item = nil;
        
//        item = [workspaceMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Save Workspace...", @"OmniInspector", bundle, @"Save Workspace menu item") action:@selector(saveWorkspace:) keyEquivalent:@""];
 //       [item setTarget:self];
        item = [workspaceMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Edit Workspaces", @"OmniInspector", bundle, @"Edit Workspaces menu item") action:@selector(editWorkspace:) keyEquivalent:@""];
        [item setTarget:self];
        if (![OIInspectorGroup isUsingASeparateMenuForWorkspaces]) {
            [workspaceMenu addItem:[NSMenuItem separatorItem]];
            [workspaceMenu addItem:[self resetPanelsItem]];
        } 
        [self _buildWorkspacesInMenu];
    }
    return workspaceMenu;
}

- (NSMenuItem *)resetPanelsItem;
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Reset Inspector Locations", @"OmniInspector", [OIInspectorRegistry bundle], @"Reset Inspector Locations menu item") action:@selector(switchToDefault:) keyEquivalent:@""];
    [item setTarget:self];
    return item;
}

- (IBAction)addWorkspace:(id)sender;
{
    NSString *name = NSLocalizedStringFromTableInBundle(@"Untitled", @"OmniInspector", [OIInspectorRegistry bundle], @"Save Workspace default title");
    if ([_workspaces containsObject:name]) {
        NSString *withNumber;
        int index = 1;
        do {
            withNumber = [NSString stringWithFormat:@"%@ %d", name, index++];
        } while ([_workspaces containsObject:withNumber]);
        name = withNumber;
    }
    
    NSString *path = [[OIInspectorRegistry bundle] pathForResource:@"OIWorkspaceSnap" ofType:@"aiff"];
    NSSound *sound = [[NSSound alloc] initWithContentsOfFile:path byReference:YES];
    [sound play];
    [_workspaces addObject:name];
    [[NSUserDefaults standardUserDefaults] setObject:_workspaces forKey:[self inspectorWorkspacesPreference]];
    [self _saveConfigurations];
    [[NSUserDefaults standardUserDefaults] setObject:[_workspaceDefaults copy] forKey:[NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], name]];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [self _buildWorkspacesInMenu];
    [_editWorkspaceTable reloadData];
    [_editWorkspaceTable selectRowIndexes:[NSIndexSet indexSetWithIndex:[_editWorkspaceTable numberOfRows]-1] byExtendingSelection:NO];
    [_editWorkspaceTable editColumn:0 row:[_editWorkspaceTable numberOfRows]-1 withEvent:nil select:YES];
}

- (IBAction)saveWorkspace:(id)sender;
{
    [self _ensureNibLoaded];
    
    [_makeWorkspaceTextField setStringValue:NSLocalizedStringFromTableInBundle(@"Untitled", @"OmniInspector", [OIInspectorRegistry bundle], @"Save Workspace default title")];
    NSWindow *window = [_makeWorkspaceTextField window];
    [window center];
    [window makeKeyAndOrderFront:self];
    [NSApp runModalForWindow:window];
}

- (IBAction)saveWorkspaceConfirmed:(id)sender;
{
    NSString *name = [_makeWorkspaceTextField stringValue];

    if ([_workspaces containsObject:name]) {
        NSString *withNumber;
        int index = 1;
        
        do {
            withNumber = [NSString stringWithFormat:@"%@-%d", name, index++];
        } while ([_workspaces containsObject:withNumber]);
        name = withNumber;
    }

    [_workspaces addObject:name];
    [[NSUserDefaults standardUserDefaults] setObject:_workspaces forKey:[self inspectorWorkspacesPreference]];
    [self _saveConfigurations];
    [[NSUserDefaults standardUserDefaults] setObject:[_workspaceDefaults copy] forKey:[NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], name]];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [self _buildWorkspacesInMenu];
    [self cancelWorkspacePanel:sender];
}

- (IBAction)editWorkspace:(id)sender;
{
    [self _ensureNibLoaded];
    
    [_editWorkspaceTable reloadData];
    [_editWorkspaceTable deselectAll:nil];
    [_deleteWorkspaceButton setEnabled:([_editWorkspaceTable numberOfSelectedRows] > 0)];
    [self tableViewSelectionDidChange:nil];  // updates the store and restore buttons
    NSPanel *window = (NSPanel *)[_editWorkspaceTable window];
    [window setFloatingPanel:YES];
    [window setHidesOnDeactivate:YES];
    [window center];
    [window makeKeyAndOrderFront:self];
//    [NSApp runModalForWindow:window];
}

static NSString *OIWorkspaceOrderPboardType = @"OIWorkspaceOrder";

- (void)awakeFromNib;
{
    [_editWorkspaceTable registerForDraggedTypes:[NSArray arrayWithObject:OIWorkspaceOrderPboardType]];
}

- (IBAction)deleteWithoutConfirmation:(id)sender;
{
    [[_editWorkspaceTable window] endEditingFor:nil];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    OFForEachIndexReverse([_editWorkspaceTable selectedRowIndexes], row) {
        [defaults removeObjectForKey:[NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], [_workspaces objectAtIndex:row]]];
        [_workspaces removeObjectAtIndex:row];
    }
    [defaults setObject:_workspaces forKey:[self inspectorWorkspacesPreference]];
    [_editWorkspaceTable reloadData];
    [self _buildWorkspacesInMenu];
}

- (IBAction)deleteWorkspace:(id)sender;
{
    [[_editWorkspaceTable window] endEditingFor:nil];
    
    NSAlert *deleteAlert = [[NSAlert alloc] init];
    [deleteAlert setAlertStyle:NSWarningAlertStyle];
    [deleteAlert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniInspector", [OIInspectorRegistry bundle], @"delete workspace OK")];
    [deleteAlert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniInspector", [OIInspectorRegistry bundle], @"delete workspace Cancel")];
    
    NSIndexSet *selectedRows = [_editWorkspaceTable selectedRowIndexes];
    if ([selectedRows count] == 1) {
	NSString *workspaceName = [_workspaces objectAtIndex:[selectedRows firstIndex]];
	[deleteAlert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Delete workspace '%@'?", @"OmniInspector", [OIInspectorRegistry bundle], @"delete workspace warning - single selection"), workspaceName]];
    } else {
	[deleteAlert setMessageText:NSLocalizedStringFromTableInBundle(@"Delete selected workspaces?", @"OmniInspector", [OIInspectorRegistry bundle], @"delete workspace warning - multiple selection")];
    }
    [deleteAlert setInformativeText:NSLocalizedStringFromTableInBundle(@"Deleted workspaces cannot be restored.", @"OmniInspector", [OIInspectorRegistry bundle], @"delete workspace warning - details")];
    
    [deleteAlert beginSheetModalForWindow:[_editWorkspaceTable window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
    if (returnCode == NSAlertFirstButtonReturn) {
        [self deleteWithoutConfirmation:nil];
    }
}

- (IBAction)cancelWorkspacePanel:(id)sender;
{
    [[(NSView *)sender window] orderOut:self];
    [NSApp stopModal];
}

- (IBAction)overwriteWorkspace:(id)sender;
{
    NSInteger row = [_editWorkspaceTable selectedRow];
    if (row < 0) {
        OBASSERT_NOT_REACHED("Action should have been disabled w/o a selection");
        NSBeep();
        return;
    }
    
    NSString *name = [_workspaces objectAtIndex:row];
    [self _saveConfigurations];
    [[NSUserDefaults standardUserDefaults] setObject:[_workspaceDefaults copy] forKey:[NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], name]];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (IBAction)restoreWorkspace:(id)sender;
{
    NSInteger row = [_editWorkspaceTable selectedRow];
    if (row < 0) {
        OBASSERT_NOT_REACHED("Action should have been disabled w/o a selection");
        NSBeep();
        return;
    }
        
    NSString *name = [_workspaces objectAtIndex:row];
    NSDictionary *newSettings = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], name]];
    if (newSettings == nil)
        return;
    
    [hiddenGroups removeAllObjects];
    [self clearAllGroups];
    [_workspaceDefaults setDictionary:newSettings];
    [self defaultsDidChange];
    [self restoreInspectorGroups];
    [self _loadConfigurations];
    [[_editWorkspaceTable window] makeKeyWindow];
}

- (IBAction)switchToWorkspace:(id)sender;
{
    NSDictionary *newSettings = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], [sender representedObject]]];
    
    if (newSettings == nil)
        return;
    
    [hiddenGroups removeAllObjects];
    [self clearAllGroups];
    [_workspaceDefaults setDictionary:newSettings];
    [self defaultsDidChange];
    [self restoreInspectorGroups];
    [self queueSelectorOnce:@selector(_loadConfigurations)];
}

- (IBAction)switchToDefault:(id)sender;
{
    _workspaceDefaults = nil;
    [hiddenGroups removeAllObjects];
    [self clearAllGroups];
    [self defaultsDidChange];
    [self restoreInspectorGroups];
    [self queueSelectorOnce:@selector(_loadConfigurations)];    
}

- (IBAction)showWorkspacesHelp:(id)sender;
{
    OBASSERT([NSApp isKindOfClass:[OAApplication class]]);  // OAApplication provides -showHelpURL:, which allows some special URLs (like "anchor:blah"). It's not provided by NSApplication.
    [(OAApplication *)NSApp showHelpURL:[[self class] _workspacesHelpURL]];
}

// The shared inspector can be created before or after the dynamic menu placeholder awakes from nib.

- (void)restoreInspectorGroups
{
    [self queueSelectorOnce:@selector(restoreInspectorGroupsWithInspectors:) withObject:inspectorControllers];
}

- (void)dynamicMenuPlaceholderSet;
{
    [self queueSelectorOnce:@selector(restoreInspectorGroupsWithInspectors:) withObject:inspectorControllers];
}

- (float)inspectorWidth;
{
    return inspectorWidth;
}

- (void)setLastWindowAskedToInspect:(NSWindow *)aWindow;
{
    lastWindowAskedToInspect = aWindow;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView;
{
    return [_workspaces count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex;
{
    if ([[aTableColumn identifier] isEqualToString:@"Name"]) {
        return [_workspaces objectAtIndex:rowIndex];
    } else {
        NSInteger fKey = rowIndex + 2;
        
        if (fKey <= 8)
            return [NSString stringWithFormat:@"F%d", (int)fKey];
        else
            return @"";
    }
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex;
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *oldName = [_workspaces objectAtIndex:rowIndex];
    NSString *oldDefault = [NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], oldName];

    NSUInteger i, count = [_workspaces count];
    for (i = 0; i < count; i++) {
        if (rowIndex >= 0 && i == (NSUInteger)rowIndex)
            continue;
        if ([anObject isEqualToString:[_workspaces objectAtIndex:i]]) {
            anObject = [anObject stringByAppendingString:@" "];
            i = 0;
        }
    }
    NSString *newDefault = [NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], anObject];
    if (![newDefault isEqualToString:oldDefault]) {
        [defaults setObject:[defaults objectForKey:oldDefault] forKey:newDefault];
        [defaults removeObjectForKey:oldDefault];
        [_workspaces replaceObjectAtIndex:rowIndex withObject:anObject];

        [[NSUserDefaults standardUserDefaults] setObject:_workspaces forKey:[self inspectorWorkspacesPreference]];
        [self _saveConfigurations];

        [self _buildWorkspacesInMenu];
    }
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation;
{
    NSArray *names = [[info draggingPasteboard] propertyListForType:OIWorkspaceOrderPboardType];

    for (NSString *name in names) {
        NSUInteger workspaceIndex = [_workspaces indexOfObject:name];
        if (workspaceIndex == NSNotFound) {
            OBASSERT_NOT_REACHED("Possible to hit this?");
            continue;
        }
        if (row >= 0 && workspaceIndex < (NSUInteger)row)
            row--;
        [_workspaces removeObjectAtIndex:workspaceIndex];
    }
    [_workspaces insertObjectsFromArray:names atIndex:row];
    [[NSUserDefaults standardUserDefaults] setObject:_workspaces forKey:[self inspectorWorkspacesPreference]];
    [tableView reloadData];
    [self _buildWorkspacesInMenu];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation;
{
    if (row == -1)
        row = [tableView numberOfRows];
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard;
{
    if ([_workspaces count] <= 1)
        return NO;
    
    NSMutableArray *names = [NSMutableArray array];
    OFForEachIndex(rowIndexes, row) {
        [names addObject:[_workspaces objectAtIndex:row]];
    }

    [pboard declareTypes:[NSArray arrayWithObject:OIWorkspaceOrderPboardType] owner:nil];
    [pboard setPropertyList:names forType:OIWorkspaceOrderPboardType];
    return YES;
}

#pragma mark - NSTableViewDelegate

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    if (tableColumn == [[tableView tableColumns] objectAtIndex:1]) {
        if ([tableView isRowSelected:row])
            [cell setTextColor:[NSColor colorWithCalibratedWhite:0.86f alpha:1]];
        else
            [cell setTextColor:[NSColor lightGrayColor]];
    } else {
        [cell setTextColor:[NSColor blackColor]];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification;
{
    [_deleteWorkspaceButton setEnabled:([_editWorkspaceTable numberOfSelectedRows] > 0)];
    [_overwriteWorkspaceButton setEnabled:([_editWorkspaceTable numberOfSelectedRows] == 1)];
    [_restoreWorkspaceButton setEnabled:([_editWorkspaceTable numberOfSelectedRows] == 1)];
}

#pragma mark - OAWindowCascadeDataSource

- (NSArray *)windowsThatShouldBeAvoided;
{
    return [self visibleWindows];
}

// this is used by Graffle to position the inspectors below the stencil palette
- (NSPoint)adjustTopLeftDefaultPositioningPoint:(NSPoint)topLeft;
{
    return topLeft;
}

#pragma mark - Private

@synthesize saveWorkspacePanel=_saveWorkspacePanel, editWorkspacePanel=_editWorkspacePanel;

+ (NSString *)_workspacesHelpURL;
{
    static NSString *helpURL = nil;
    if (helpURL == nil) {
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        helpURL = [infoDictionary objectForKey:OIWorkspacesHelpURLKey];
    }
    return helpURL;
}

- (void)_ensureNibLoaded;
{
    if (!_makeWorkspaceTextField) {
        [[OIInspectorRegistry bundle] loadNibNamed:@"OIInspectorWorkspacePanels" owner:self topLevelObjects:NULL];
        
        // Hide the help button if we don't have a help URL
        if ([[self class] _workspacesHelpURL] == nil) {
            [_workspacesHelpButton setHidden:YES];
        }
    }
}

- (OIInspectorController *)_registerInspector:(OIInspector *)inspector;
{
    OBPRECONDITION(inspector);
    OIInspectorController *controller = [self controllerWithInspector:inspector];    
    [inspectorControllers addObject:controller];
    return controller;
}

- (void)_inspectWindow:(NSWindow *)window queue:(BOOL)queue onlyIfVisible:(BOOL)onlyIfVisible updateInspectors:(BOOL)updateInspectors;
{
    [self setLastWindowAskedToInspect:window];
    
    if (queue) {
        if (!registryFlags.isInspectionQueued) {
            [self queueSelector:@selector(_queuedRecalculateInspectorsAndInspectWindow:updateInspectors:) withInt:onlyIfVisible withInt:updateInspectors];
            registryFlags.isInspectionQueued = YES;
        }
    } else
        [self _recalculateInspectionSetIfVisible:onlyIfVisible updateInspectors:updateInspectors];
}

// Used 'int' since there isn't a queueSelector:withBool:withBool:
- (void)_queuedRecalculateInspectorsAndInspectWindow:(int)onlyIfVisible updateInspectors:(int)updateInspectors;
{
    // Ignore queued selectors that get invoked after a manual display
    if (!registryFlags.isInspectionQueued)
        return;
    [self _recalculateInspectionSetIfVisible:(BOOL)onlyIfVisible updateInspectors:(BOOL)updateInspectors];
}

/// Helper to do the right thing for embedded/floating inspectors. With a common floating inspector, we want the various controllers to inspect the objects in the main window (stored here as lastWindowAskedToInspect - see the various NSWindow... notifications we observe on this class). With an embedded inspector sidebar, though, we want the controllers to be tied to their own window.
- (NSWindow *)_windowForGettingInspectedObjects;
{
    NSArray *controllers = self.controllers;
    BOOL hasFloating = NO;
    OBASSERT([controllers count] > 0);
    if ([controllers count] == 0)
        return nil;
    
    for (OIInspectorController *controller in controllers) {
        if (controller.interfaceType == OIInspectorInterfaceTypeFloating) {
            hasFloating = YES;
        }
    }
    
    if (hasFloating) {
        return lastWindowAskedToInspect;
    }
    
    // All the controllers are embedded - we can ask the app delegate what window they belong in
    Class appDelegateClass = [[NSApp delegate] class];
    if (OBClassImplementingMethod(appDelegateClass, @selector(windowForInspectorRegistry:)) == [NSObject class]) {
        // The app delegate doesn't implement the appropriate method - fall back on legacy behavior and return the last window that asked for inspection
        return lastWindowAskedToInspect;
    }
    
    return [[NSApp delegate] windowForInspectorRegistry:self];
}

- (void)_getInspectedObjects;
{
    static BOOL isFloating = YES;
    NSWindow *window = [self _windowForGettingInspectedObjects];
    
    // Don't float over non-document windows, unless the window in question is already at a higher level.
    // For example, the Quick Entry panel in OmniFocus -- calling -orderFront: ends up screwing up its exclusive activation support.  <bug://bugs/41806> (Calling up QE shows OF window [Quick Entry])
    
    NSWindowController *windowController = nil;
    if ([[window delegate] isKindOfClass:[NSWindowController class]])
	windowController = (NSWindowController *)[window delegate];
    
    BOOL hasDocument = ([windowController document] != nil);
    
    BOOL shouldFloat = window == nil || [window level] > NSFloatingWindowLevel || hasDocument;
    if (isFloating != shouldFloat) {
        for (OIInspectorGroup *group in [self groups])
            [group setFloating:shouldFloat];
        isFloating = shouldFloat;
        
        if (!shouldFloat)
            [window orderFront:self];
    }

    // Clear the old inspection
    inspectionSet = [[OIInspectionSet alloc] init];

    // Fill the inspection set across all inspectable controllers in the responder chain, starting from the 'oldest' (probably the app delegate) to 'newest' the first responder.  This allows responders that are 'closer' to the user to override inspection from 'further' responders.
    NSResponder *responder = [window firstResponder];
    if (!responder)
        responder = window;
    NSMutableSet *seenControllers = [NSMutableSet set];
    [responder applyToResponderChain: ^ BOOL (id target) {
        // Create a block with this behavior so that we can then apply the exact same behavior to both our target and its delegate (if it has a delegate)
        OAResponderChainApplier addInspectedObjects = ^ BOOL (id target) {
            if ([target conformsToProtocol:@protocol(OIInspectableController)]) {
                // A controller may be accessible along two paths in the responder chain by being the delegate for multiple NSResponders.  Only give each object one chance to add its stuff, otherwise controllers that want to override a particular class via -[OIInspectionSet removeObjectsWithClass:] may itself be overriden by the duplicate delegate!
                if ([seenControllers member:target] == nil) {
                    [seenControllers addObject:target];
                    [(id <OIInspectableController>)target addInspectedObjects:inspectionSet];
                    if ([target respondsToSelector:@selector(inspectionIdentifierForInspectionSet:)] && _currentInspectionIdentifier == nil) {
                        _currentInspectionIdentifier = [[target inspectionIdentifierForInspectionSet:inspectionSet] copy];
                    }
                }
            }
            return YES; // continue searching
        };
        
        if (!addInspectedObjects(target)) {
            return NO;
        }
        if ([target respondsToSelector:@selector(delegate)] && !addInspectedObjects([(id)target delegate])) {
            return NO;
        }
        return YES;
    }];
}

- (void)_recalculateInspectionSetIfVisible:(BOOL)onlyIfVisible updateInspectors:(BOOL)updateInspectors;
{
    registryFlags.isInspectionQueued = NO;
    _currentInspectionIdentifier = nil;

    // Don't calculate inspection set if it would be pointless
    if (onlyIfVisible && ![self hasVisibleInspector]) {
        inspectionSet = nil;
        [self _postInspectionSetChangedNotificationAndUpdateInspectors:NO];
    } else {
        [self _getInspectedObjects];
        [self _postInspectionSetChangedNotificationAndUpdateInspectors:updateInspectors];
    }
}

- (void)_postInspectionSetChangedNotificationAndUpdateInspectors:(BOOL)updateInspectors;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OIInspectionSetChangedNotification object:self userInfo:nil];
    
    // Some callers know we don't need to update the inspectors themselves (perhaps we have no visible inspectors or they will be directly updated soon).
    if (updateInspectors)
        [inspectorControllers makeObjectsPerformSelector:@selector(updateInspector)];
}

- (void)_inspectWindowNotification:(NSNotification *)notification;
{
    NSWindow *window = [notification object];
    
    if (window != lastMainWindowBeforeAppSwitch)
        [self _inspectWindow:window queue:YES onlyIfVisible:YES updateInspectors:YES];
}

- (void)_uninspectWindowNotification:(NSNotification *)notification;
{
    if (lastMainWindowBeforeAppSwitch == nil)
        [self _inspectWindow:nil queue:YES onlyIfVisible:YES updateInspectors:YES];
}

- (void)_applicationDidActivate:(NSNotification *)note;
{
    if (lastMainWindowBeforeAppSwitch) {
        [self _inspectWindow:lastMainWindowBeforeAppSwitch queue:YES onlyIfVisible:YES updateInspectors:YES];
	lastMainWindowBeforeAppSwitch = nil;
    }
}

- (void)_applicationWillResignActive:(NSNotification *)notification;
{
    lastMainWindowBeforeAppSwitch = [NSApp mainWindow];
}

- (void)_windowWillClose:(NSNotification *)note;
{
    NSWindow *window = [note object];
    if (window == lastWindowAskedToInspect) {
        if (!registryFlags.isInvalidated) // if we're closing this thing down, don't get a new inspection set in the middle of window teardown.
            [self _inspectWindow:nil queue:NO onlyIfVisible:NO updateInspectors:YES];
        
        lastMainWindowBeforeAppSwitch = nil;
    } else if (window == lastMainWindowBeforeAppSwitch) {
        lastMainWindowBeforeAppSwitch = nil;
    }
}



- (void)controllerStartedRunning:(OFController *)controller;
{
    if (controller != nil)
        [controller removeObserver:self];
    
    if (!registryFlags.isListeningForNotifications) {
        NSNotificationCenter *defaultNotificationCenter = [NSNotificationCenter defaultCenter];

	// Since we bail on updating the UI if the window isn't visible, and since panels aren't visible when the app isn't active, we need to try again when the app activates
	[defaultNotificationCenter addObserver:self selector:@selector(_applicationDidActivate:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];

        // While the Inspector is visible, watch for any window to become main.  When that happens, determine if that window's delegate responds to the OAInspectableControllerProtocol, and act accordingly.
        [defaultNotificationCenter addObserver:self selector:@selector(_applicationWillResignActive:) name:NSApplicationWillResignActiveNotification object:NSApp];
        [defaultNotificationCenter addObserver:self selector:@selector(_inspectWindowNotification:) name:NSWindowDidBecomeMainNotification object:nil];
        [defaultNotificationCenter addObserver:self selector:@selector(_uninspectWindowNotification:) name:NSWindowDidResignMainNotification object:nil];
        
	// Listen for all window close notifications; this is easier than keeping track of subscribing only once if lastWindowAskedToInspect and lastMainWindowBeforeAppSwitch are the same but twice if they differ (but not if on is nil, etc).  There aren't a huge number of these notifications anyway.
	[defaultNotificationCenter addObserver:self selector:@selector(_windowWillClose:) name:NSWindowWillCloseNotification object:nil];

        registryFlags.isListeningForNotifications = YES;
        [self queueSelectorOnce:@selector(_loadConfigurations)];        
    }
    
    [self restoreInspectorGroups];
}

- (void)configurationsChanged;
{
    if (configurationsChangedTimer)
        [configurationsChangedTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    else {
        configurationsChangedTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(_inspectorConfigurationsChanged:) userInfo:nil repeats:NO];
        [[NSProcessInfo processInfo] disableSuddenTermination];
    }
}

- (void)_inspectorConfigurationsChanged:(NSTimer *)theTimer;
{
    [self _saveConfigurations];
    [self defaultsDidChange];
    [[NSProcessInfo processInfo] enableSuddenTermination];
    configurationsChangedTimer = nil;
}

- (void)_appWillTerminate:(NSNotification *)notification
{
    [self _saveConfigurations];
    [self defaultsDidChange];
}

- (void)_saveConfigurations;
{
    NSMutableDictionary *config = [NSMutableDictionary dictionary];
    
    for (OIInspectorController *controller in inspectorControllers)
        if ([[controller inspector] respondsToSelector:@selector(configuration)])
            [config setObject:[[controller inspector] configuration] forKey:[controller identifier]];

    [_workspaceDefaults setObject:config forKey:@"_Configurations"];
    [self saveExistingGroups];
}

- (void)_loadConfigurations;
{
    NSDictionary *config = [_workspaceDefaults objectForKey:@"_Configurations"];
    
    for (OIInspectorController *controller in inspectorControllers)
        if ([[controller inspector] respondsToSelector:@selector(loadConfiguration:)])
            [[controller inspector] loadConfiguration:[config objectForKey:[controller identifier]]];
}

- (void)_applicationDidFinishRestoringWindowsNotification:(NSNotification *)notification;
{
    _applicationDidFinishRestoringWindows = YES;
    
    [_groupsToShowAfterWindowRestoration makeObjectsPerformSelector:@selector(_showGroup)];
    _groupsToShowAfterWindowRestoration = nil;
}

@synthesize applicationDidFinishRestoringWindows = _applicationDidFinishRestoringWindows;

- (void)addGroupToShowAfterWindowRestoration:(OIInspectorGroup *)group;
{
    if (!_groupsToShowAfterWindowRestoration)
        _groupsToShowAfterWindowRestoration = [[NSMutableArray alloc] init];
    [_groupsToShowAfterWindowRestoration addObject:group];
}

@end


#import "OIInspectorWindow.h"

@implementation NSView (OIInspectorExtensions)

// This can be used by views that are normally inspectable but that can also themselves be inside an inspector (in which case it is still for them to update the inspector).
- (BOOL)isInsideInspector;
{
    return [[self window] isKindOfClass:[OIInspectorWindow class]];
}

@end


@implementation NSObject (OIInspectorRegistryApplicationDelegate)

- (OIInspectorRegistry *)inspectorRegistryForWindow:(NSWindow *)window;
{
    static dispatch_once_t onceToken;
    if (self != [NSApp delegate]) {
        dispatch_once(&onceToken, ^{
            NSLog(@"WARNING: You attempted to call %@ on an object that is not the application delegate or does not properly subclass the required inspector registry method. You should ensure you override %@ on your application delegate (without calling super) and call it only on that delegate. Only warning once.", NSStringFromSelector(_cmd), NSStringFromSelector(_cmd));
        });
    }
    
    return nil;
}

- (NSWindow *)windowForInspectorRegistry:(OIInspectorRegistry *)inspectorRegistry;
{
    static dispatch_once_t onceToken;
    if (self != [NSApp delegate]) {
        dispatch_once(&onceToken, ^{
            NSLog(@"WARNING: You attempted to call %@ on an object that is not the application delegate or does not properly subclass the required inspector registry method. You should ensure you override %@ on your application delegate (without calling super) and call it only on that delegate. Only warning once.", NSStringFromSelector(_cmd), NSStringFromSelector(_cmd));
        });
    }
    
    return nil;
}

@end

