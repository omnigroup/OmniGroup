// Copyright 2002-2008, 2010 Omni Development, Inc.  All rights reserved.
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
#import <OmniAppKit/OAApplication.h>
#import <OmniAppKit/OAWindowCascade.h>

#import "OIInspectableControllerProtocol.h"
#import "OIInspectionSet.h"
#import "OIInspector.h"
#import "OIInspectorController.h"
#import "OIInspectorGroup.h"
#import "OITabbedInspector.h"


#import "OIInspectionSet.h"

RCS_ID("$Id$");

@interface OIInspectorRegistry (/*Private*/) <NSTableViewDelegate>
+ (NSString *)_workspacesHelpURL;
- (void)_ensureNibLoaded;
- (OIInspectorController *)_registerInspector:(OIInspector *)inspector;
- (void)_inspectWindow:(NSWindow *)window queue:(BOOL)queue onlyIfVisible:(BOOL)onlyIfVisible updateInspectors:(BOOL)updateInspectors;
- (void)_queuedRecalculateInspectorsAndInspectWindow:(int)onlyIfVisible updateInspectors:(int)updateInspectors;
- (void)_mergeInspectedObjectsFromPotentialController:(id)object seenControllers:(NSMutableSet *)seenControllers;
- (void)_mergeInspectedObjectsFromResponder:(NSResponder *)responder seenControllers:(NSMutableSet *)seenControllers;
- (void)_getInspectedObjects;
- (void)_recalculateInspectionSetIfVisible:(BOOL)onlyIfVisible updateInspectors:(BOOL)updateInspectors;
- (void)_selectionMightHaveChangedNotification:(NSNotification *)notification;
- (void)_inspectWindowNotification:(NSNotification *)notification;
- (void)_uninspectWindowNotification:(NSNotification *)notification;
- (void)_windowWillClose:(NSNotification *)note;
- (void)_saveConfigurations;
- (void)_loadConfigurations;
@end

NSString *OIInspectorSelectionDidChangeNotification = @"OIInspectorSelectionDidChangeNotification";
NSString *OIWorkspacesHelpURLKey = @"OIWorkspacesHelpURL";

static NSMutableArray *additionalPanels = nil;
static NSString *inspectorDefaultsVersion = nil;

@implementation OIInspectorRegistry

+ (void)initialize;
{
    OBINITIALIZE;
    additionalPanels = [[NSMutableArray alloc] init];
}

+ (void)setInspectorDefaultsVersion:(NSString *)versionString;
{
    [inspectorDefaultsVersion release];
    inspectorDefaultsVersion = [versionString retain];
}

+ (OIInspectorController *)controllerWithInspector:(OIInspector *)inspector;
{
    // This method is here so that it can be overridden by app-specific subclasses of OIInspectorRegistry
    return [[[OIInspectorController alloc] initWithInspector:inspector] autorelease];
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
    
    OIInspectorRegistry *registry = [self sharedInspector]; // Make sure the class has woken up
    
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
        [(OITabbedInspector *)parent registerInspectorDictionary:descriptionDictionary bundle:bundle];
    } else {
        OIInspector *inspector = [OIInspector newInspectorWithDictionary:descriptionDictionary bundle:bundle];
        [registry _registerInspector:inspector];
        [inspector release];
    }
}

+ (Class)sharedInspectorClass
{
    static Class sharedInspectorClass = Nil;

    if (sharedInspectorClass == Nil) {
        // Allow the main bundle to request a subclass
        NSString *className = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"OIInspectorRegistryClass"];
        if (className) {
            if (!(sharedInspectorClass = NSClassFromString(className)))
                NSLog(@"Unable to find %@ subclass '%@'", NSStringFromClass(self), className);
            if (!OBClassIsSubclassOfClass(sharedInspectorClass, self)) {
                NSLog(@"'%@' is not a subclass of '%@'", className, NSStringFromClass(self));
                sharedInspectorClass = Nil;
            }
        }
        if (!sharedInspectorClass)
            sharedInspectorClass = self;
    }
    
    return sharedInspectorClass;
}

+ (OIInspectorRegistry *)sharedInspector;
{
    static OIInspectorRegistry *sharedInspector = nil;

    if (sharedInspector == nil) {
        sharedInspector = [[[self sharedInspectorClass] alloc] init];
        [OAWindowCascade addDataSource:sharedInspector];
        [OAWindowCascade avoidFontPanel];
        [OAWindowCascade avoidColorPanel];
    }
    return sharedInspector;
}

static NSMutableArray *hiddenGroups = nil;
static NSMutableArray *hiddenPanels = nil;
    
+ (void)tabShowHidePanels;
{
    NSMutableArray *visibleGroups = [NSMutableArray array];
    NSMutableArray *visiblePanels = [NSMutableArray array];
    NSArray *existingGroups = [OIInspectorGroup groups];
    
    for (OIInspectorGroup *group in existingGroups) {
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
        [hiddenGroups release];
        hiddenGroups = [visibleGroups retain];
        [hiddenPanels release];
        hiddenPanels = [visiblePanels retain];
    } else if ([hiddenGroups count] || [hiddenPanels count]) {
        [hiddenGroups makeObjectsPerformSelector:@selector(showGroup)];
        [hiddenGroups release];
        hiddenGroups = nil;
        [hiddenPanels makeObjectsPerformSelector:@selector(orderFront:) withObject:self];
        [hiddenPanels release];
        hiddenPanels = nil;
    } else {
        [existingGroups makeObjectsPerformSelector:@selector(showGroup)];
        
        for (NSWindowController *controller in additionalPanels)
            [[controller window] orderFront:self];
    }
}

/*" Shows all the registered inspectors.  Returns YES if any additional inspectors become visible. "*/
+ (BOOL)showAllInspectors;
{
    BOOL shownAny = NO;
    
    for (OIInspectorGroup *group in [OIInspectorGroup groups])
        if (![group isVisible]) {
            shownAny = YES;
            [group showGroup];
        }
    
    [hiddenGroups removeAllObjects];
    return shownAny;
}

/*" Hides all the registered inspectors.  Returns YES if any additional inspectors become hidden. "*/
+ (BOOL)hideAllInspectors;
{
    BOOL hiddenAny = NO;

    for (OIInspectorGroup *group in [OIInspectorGroup groups]) {
        if ([group isVisible]) {
            hiddenAny = YES;
            [group hideGroup];
            [hiddenGroups addObject:group];
        }
    }

    return hiddenAny;
}

+ (void)toggleAllInspectors;
{
    if (![self showAllInspectors])
        [self hideAllInspectors];
}

+ (void)updateInspector;
{
    [[self sharedInspector] _inspectWindow:[NSApp mainWindow] queue:YES onlyIfVisible:YES updateInspectors:YES];
}

+ (void)updateInspectionSetImmediatelyAndUnconditionally;
{
    [[self sharedInspector] _inspectWindow:[NSApp mainWindow] queue:NO onlyIfVisible:NO updateInspectors:NO];
}

+ (void)clearInspectionSet;
{
    [[[self sharedInspector] inspectionSet] removeAllObjects];
    [[self sharedInspector] inspectionSetChanged];
}

- (OIInspectorController *)controllerWithIdentifier:(NSString *)anIdentifier;
{
    OFForEachInArray(inspectorControllers, OIInspectorController *, anInspector, {
        if ([[anInspector identifier] isEqualToString:anIdentifier])
            return anInspector;
    });
    
    return nil;
}

- (BOOL)hasSingleInspector;
{
    return ([inspectorControllers count] == 1);
}

- (BOOL)hasVisibleInspector;
/*" Returns YES if any of the registered inspectors are on screen and expanded. "*/
{
    for (OIInspectorController *controller in inspectorControllers)
        if ([[controller window] isVisible] && [controller isExpanded])
            return YES;
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

- init
{
    [super init];
    
    inspectorControllers = [[NSMutableArray alloc] init];

    workspaceDefaults = [[[NSUserDefaults standardUserDefaults] objectForKey:[self inspectorPreference]] mutableCopy];
    if (!workspaceDefaults)
        workspaceDefaults = [[NSMutableDictionary alloc] init];
    workspaces = [[[NSUserDefaults standardUserDefaults] objectForKey:[self inspectorWorkspacesPreference]] mutableCopy];
    if (!workspaces)
        workspaces = [[NSMutableArray alloc] init];

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
    
    if (inspectorWidthString) {
        float specifiedInspectorWidth = [inspectorWidthString floatValue];
        inspectorWidth = MAX(inspectorWidth, specifiedInspectorWidth);
    }
    
    if (inspectorPlists == nil)
        NSLog(@"No OIInspectors in %@", mainBundle);
    
    unsigned inspectorOrder = 0;
    for (NSDictionary *inspectorPlist in inspectorPlists) {
        @try {
            OIInspector *inspector = [OIInspector newInspectorWithDictionary:inspectorPlist bundle:nil];
            [inspector setDefaultOrderingWithinGroup:inspectorOrder++];
            [self _registerInspector:inspector];
            [inspector release];
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

static BOOL objectInterestsInspectorP(id anObject, void *anInspector)
{
    return [(OIInspector *)anInspector mayInspectObject:anObject];
}

- (NSArray *)copyObjectsInterestingToInspector:(OIInspector *)anInspector;
{
    if ([anInspector respondsToSelector:@selector(mayInspectObject:)]) {
        return [inspectionSet copyObjectsSatisfyingPredicateFunction:objectInterestsInspectorP context:(void *)anInspector];
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
    return [[inspectionSet copyObjectsSatisfyingPredicate:[NSComparisonPredicate isKindOfClassPredicate:aClass]] autorelease];
}

- (NSArray *)inspectedObjects;
{
    return [inspectionSet allObjects];
}

- (OIInspectionSet *)inspectionSet;
    /*" This method allows fine tuning of the inspection.  If the inspection set is changed, -inspectionSetChanged must be called to update the inspectors "*/
{
    return inspectionSet;
}

- (void)inspectionSetChanged;
{
    [inspectorControllers makeObjectsPerformSelector:@selector(updateInspector)];
}

- (NSMutableDictionary *)workspaceDefaults;
{
    return workspaceDefaults;
}

- (void)defaultsDidChange;
{
    if (workspaceDefaults) {
        [[NSUserDefaults standardUserDefaults] setObject:[[workspaceDefaults copy] autorelease] forKey:[self inspectorPreference]];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[self inspectorPreference]];
        workspaceDefaults = [[[NSUserDefaults standardUserDefaults] objectForKey:[self inspectorPreference]] mutableCopy];
        if (!workspaceDefaults)
            workspaceDefaults = [[NSMutableDictionary alloc] init];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
//    if ([item action] == @selector(editWorkspace:))
//        return [workspaces count] > 0;
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

    if ([workspaces count]) {
        unichar functionChar = NSF2FunctionKey, lastFunctionChar = NSF8FunctionKey;
        
        [workspaceMenu addItem:[NSMenuItem separatorItem]];
        
        for (NSString *title in workspaces) {
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
    return [item autorelease];
}

- (IBAction)addWorkspace:(id)sender;
{
    NSString *name = NSLocalizedStringFromTableInBundle(@"Untitled", @"OmniInspector", [OIInspectorRegistry bundle], @"Save Workspace default title");
    if ([workspaces containsObject:name]) {
        NSString *withNumber;
        int index = 1;
        do {
            withNumber = [NSString stringWithFormat:@"%@ %d", name, index++];
        } while ([workspaces containsObject:withNumber]);
        name = withNumber;
    }
    
    NSString *path = [[OIInspectorRegistry bundle] pathForResource:@"OIWorkspaceSnap" ofType:@"aiff"];
    NSSound *sound = [[[NSSound alloc] initWithContentsOfFile:path byReference:YES] autorelease];
    [sound play];
    [workspaces addObject:name];
    [[NSUserDefaults standardUserDefaults] setObject:workspaces forKey:[self inspectorWorkspacesPreference]];
    [self _saveConfigurations];
    [[NSUserDefaults standardUserDefaults] setObject:[[workspaceDefaults copy] autorelease] forKey:[NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], name]];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [self _buildWorkspacesInMenu];
    [editWorkspaceTable reloadData];
    [editWorkspaceTable selectRowIndexes:[NSIndexSet indexSetWithIndex:[editWorkspaceTable numberOfRows]-1] byExtendingSelection:NO];
    [editWorkspaceTable editColumn:0 row:[editWorkspaceTable numberOfRows]-1 withEvent:nil select:YES];
}

- (void)saveWorkspace:sender;
{
    [self _ensureNibLoaded];
    
    [newWorkspaceTextField setStringValue:NSLocalizedStringFromTableInBundle(@"Untitled", @"OmniInspector", [OIInspectorRegistry bundle], @"Save Workspace default title")];
    NSWindow *window = [newWorkspaceTextField window];
    [window center];
    [window makeKeyAndOrderFront:self];
    [NSApp runModalForWindow:window];
}

- (void)saveWorkspaceConfirmed:sender;
{
    NSString *name = [newWorkspaceTextField stringValue];

    if ([workspaces containsObject:name]) {
        NSString *withNumber;
        int index = 1;
        
        do {
            withNumber = [NSString stringWithFormat:@"%@-%d", name, index++];
        } while ([workspaces containsObject:withNumber]);
        name = withNumber;
    }

    [workspaces addObject:name];
    [[NSUserDefaults standardUserDefaults] setObject:workspaces forKey:[self inspectorWorkspacesPreference]];
    [self _saveConfigurations];
    [[NSUserDefaults standardUserDefaults] setObject:[[workspaceDefaults copy] autorelease] forKey:[NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], name]];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [self _buildWorkspacesInMenu];
    [self cancelWorkspacePanel:sender];
}

- (void)editWorkspace:sender;
{
    [self _ensureNibLoaded];
    
    [editWorkspaceTable reloadData];
    [editWorkspaceTable deselectAll:nil];
    [deleteWorkspaceButton setEnabled:([editWorkspaceTable numberOfSelectedRows] > 0)];
    [self tableViewSelectionDidChange:nil];  // updates the store and restore buttons
    NSPanel *window = (NSPanel *)[editWorkspaceTable window];
    [window setFloatingPanel:YES];
    [window setHidesOnDeactivate:YES];
    [window center];
    [window makeKeyAndOrderFront:self];
//    [NSApp runModalForWindow:window];
}

static NSString *OIWorkspaceOrderPboardType = @"OIWorkspaceOrder";

- (void)awakeFromNib;
{
    [editWorkspaceTable registerForDraggedTypes:[NSArray arrayWithObject:OIWorkspaceOrderPboardType]];
}

- (IBAction)deleteWithoutConfirmation:(id)sender;
{
    [[editWorkspaceTable window] endEditingFor:nil];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    OFForEachIndexReverse([editWorkspaceTable selectedRowIndexes], row) {
        [defaults removeObjectForKey:[NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], [workspaces objectAtIndex:row]]];
        [workspaces removeObjectAtIndex:row];
    }
    [defaults setObject:workspaces forKey:[self inspectorWorkspacesPreference]];
    [editWorkspaceTable reloadData];
    [self _buildWorkspacesInMenu];
}

- (void)deleteWorkspace:sender;
{
    [[editWorkspaceTable window] endEditingFor:nil];
    
    NSAlert *deleteAlert = [[[NSAlert alloc] init] autorelease];
    [deleteAlert setAlertStyle:NSWarningAlertStyle];
    [deleteAlert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniInspector", [OIInspectorRegistry bundle], @"delete workspace OK")];
    [deleteAlert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniInspector", [OIInspectorRegistry bundle], @"delete workspace Cancel")];
    
    NSIndexSet *selectedRows = [editWorkspaceTable selectedRowIndexes];
    if ([selectedRows count] == 1) {
	NSString *workspaceName = [workspaces objectAtIndex:[selectedRows firstIndex]];
	[deleteAlert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Delete workspace '%@'?", @"OmniInspector", [OIInspectorRegistry bundle], @"delete workspace warning - single selection"), workspaceName]];
    } else {
	[deleteAlert setMessageText:NSLocalizedStringFromTableInBundle(@"Delete selected workspaces?", @"OmniInspector", [OIInspectorRegistry bundle], @"delete workspace warning - multiple selection")];
    }
    [deleteAlert setInformativeText:NSLocalizedStringFromTableInBundle(@"Deleted workspaces cannot be restored.", @"OmniInspector", [OIInspectorRegistry bundle], @"delete workspace warning - details")];
    
    [deleteAlert beginSheetModalForWindow:[editWorkspaceTable window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
    if (returnCode == NSAlertFirstButtonReturn) {
        [self deleteWithoutConfirmation:nil];
    }
}

- (void)cancelWorkspacePanel:sender;
{
    [[sender window] orderOut:self];
    [NSApp stopModal];
}

- (IBAction)overwriteWorkspace:(id)sender;
{
    NSInteger row = [editWorkspaceTable selectedRow];
    if (row < 0) {
        OBASSERT_NOT_REACHED("Action should have been disabled w/o a selection");
        NSBeep();
        return;
    }
    
    NSString *name = [workspaces objectAtIndex:row];
    [self _saveConfigurations];
    [[NSUserDefaults standardUserDefaults] setObject:[[workspaceDefaults copy] autorelease] forKey:[NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], name]];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (IBAction)restoreWorkspace:(id)sender;
{
    NSInteger row = [editWorkspaceTable selectedRow];
    if (row < 0) {
        OBASSERT_NOT_REACHED("Action should have been disabled w/o a selection");
        NSBeep();
        return;
    }
        
    NSString *name = [workspaces objectAtIndex:row];
    NSDictionary *newSettings = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], name]];
    if (newSettings == nil)
        return;
    
    [hiddenGroups removeAllObjects];
    [OIInspectorGroup clearAllGroups];
    [workspaceDefaults setDictionary:newSettings];
    [self defaultsDidChange];
    [self restoreInspectorGroups];
    [self _loadConfigurations];
    [[editWorkspaceTable window] makeKeyWindow];
}

- (void)switchToWorkspace:sender;
{
    NSDictionary *newSettings = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], [sender representedObject]]];
    
    if (newSettings == nil)
        return;
    
    [hiddenGroups removeAllObjects];
    [OIInspectorGroup clearAllGroups];
    [workspaceDefaults setDictionary:newSettings];
    [self defaultsDidChange];
    [self restoreInspectorGroups];
    [self queueSelectorOnce:@selector(_loadConfigurations)];
}

- (void)switchToDefault:sender;
{
    [workspaceDefaults release];
    workspaceDefaults = nil;
    [hiddenGroups removeAllObjects];
    [OIInspectorGroup clearAllGroups];
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
    [OIInspectorGroup queueSelectorOnce:@selector(restoreInspectorGroupsWithInspectors:) withObject:inspectorControllers];
}

- (void)dynamicMenuPlaceholderSet;
{
    [OIInspectorGroup queueSelectorOnce:@selector(restoreInspectorGroupsWithInspectors:) withObject:inspectorControllers];
}

- (float)inspectorWidth;
{
    return inspectorWidth;
}

- (void)setLastWindowAskedToInspect:(NSWindow *)aWindow;
{
    [lastWindowAskedToInspect release];
    lastWindowAskedToInspect = [aWindow retain];
}

#pragma mark NSTableView data source methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView;
{
    return [workspaces count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex;
{
    if ([[aTableColumn identifier] isEqualToString:@"Name"]) {
        return [workspaces objectAtIndex:rowIndex];
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
    NSString *oldName = [workspaces objectAtIndex:rowIndex];
    NSString *oldDefault = [NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], oldName];

    NSUInteger i, count = [workspaces count];
    for (i = 0; i < count; i++) {
        if (rowIndex >= 0 && i == (NSUInteger)rowIndex)
            continue;
        if ([anObject isEqualToString:[workspaces objectAtIndex:i]]) {
            anObject = [anObject stringByAppendingString:@" "];
            i = 0;
        }
    }
    NSString *newDefault = [NSString stringWithFormat:@"%@-%@", [self inspectorWorkspacesPreference], anObject];
    if (![newDefault isEqualToString:oldDefault]) {
        [defaults setObject:[defaults objectForKey:oldDefault] forKey:newDefault];
        [defaults removeObjectForKey:oldDefault];
        [workspaces replaceObjectAtIndex:rowIndex withObject:anObject];

        [[NSUserDefaults standardUserDefaults] setObject:workspaces forKey:[self inspectorWorkspacesPreference]];
        [self _saveConfigurations];

        [self _buildWorkspacesInMenu];
    }
}

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

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation;
{
    NSArray *names = [[info draggingPasteboard] propertyListForType:OIWorkspaceOrderPboardType];

    for (NSString *name in names) {
        NSUInteger workspaceIndex = [workspaces indexOfObject:name];
        if (workspaceIndex == NSNotFound) {
            OBASSERT_NOT_REACHED("Possible to hit this?");
            continue;
        }
        if (row >= 0 && workspaceIndex < (NSUInteger)row)
            row--;
        [workspaces removeObjectAtIndex:workspaceIndex];
    }
    [workspaces insertObjectsFromArray:names atIndex:row];
    [[NSUserDefaults standardUserDefaults] setObject:workspaces forKey:[self inspectorWorkspacesPreference]];
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
    if ([workspaces count] <= 1)
        return NO;
    
    NSMutableArray *names = [NSMutableArray array];
    OFForEachIndex(rowIndexes, row) {
        [names addObject:[workspaces objectAtIndex:row]];
    }

    [pboard declareTypes:[NSArray arrayWithObject:OIWorkspaceOrderPboardType] owner:nil];
    [pboard setPropertyList:names forType:OIWorkspaceOrderPboardType];
    return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification;
{
    [deleteWorkspaceButton setEnabled:([editWorkspaceTable numberOfSelectedRows] > 0)];
    [overwriteWorkspaceButton setEnabled:([editWorkspaceTable numberOfSelectedRows] == 1)];
    [restoreWorkspaceButton setEnabled:([editWorkspaceTable numberOfSelectedRows] == 1)];
}


//
// OAWindowCascade data source
//

- (NSArray *)windowsThatShouldBeAvoided;
{
    return [OIInspectorGroup visibleWindows];
}

// this is used by Graffle to position the inspectors below the stencil palette
- (NSPoint)adjustTopLeftDefaultPositioningPoint:(NSPoint)topLeft;
{
    return topLeft;
}


#pragma mark Weak retain stubs

// We never get deallocated, so we don't really need to implement the weak retain API.
- (void)incrementWeakRetainCount { }
- (void)decrementWeakRetainCount { }
- (id)strongRetain { return [self retain]; }
- (void)invalidateWeakRetains
{
    [[OFController sharedController] removeObserver:self];
}

#pragma mark -
#pragma mark Private

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
    if (!newWorkspaceTextField) {
        [[OIInspectorRegistry bundle] loadNibNamed:@"OIInspectorWorkspacePanels" owner:self];
        
        // Hide the help button if we don't have a help URL
        if ([[self class] _workspacesHelpURL] == nil) {
            [workspacesHelpButton setHidden:YES];
        }
    }
}

- (OIInspectorController *)_registerInspector:(OIInspector *)inspector;
{
    OBPRECONDITION(inspector);
    OIInspectorController *controller = [[self class] controllerWithInspector:inspector];    
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

- (void)_mergeInspectedObjectsFromPotentialController:(id)object seenControllers:(NSMutableSet *)seenControllers;
{
    if ([object conformsToProtocol:@protocol(OIInspectableController)]) {
        // A controller may be accessible along two paths in the responder chain by being the delegate for multiple NSResponders.  Only give each object one chance to add its stuff, otherwise controllers that want to override a particular class via -[OIInspectionSet removeObjectsWithClass:] may itself be overriden by the duplicate delegate!
        if ([seenControllers member:object] == nil) {
            [seenControllers addObject:object];
            [(id <OIInspectableController>)object addInspectedObjects:inspectionSet];
        }
    }
}

- (void)_mergeInspectedObjectsFromResponder:(NSResponder *)responder seenControllers:(NSMutableSet *)seenControllers;
{
    [self _mergeInspectedObjectsFromPotentialController:responder seenControllers:seenControllers];
    
    // Also allow delegates of responders to be inspectable.  They follow the object of which they are a delegate so they can override it
    if ([responder respondsToSelector:@selector(delegate)])
        [self _mergeInspectedObjectsFromPotentialController:[(id)responder delegate] seenControllers:seenControllers];

    NSResponder *nextResponder = [responder nextResponder];

    if (nextResponder) {
        [self _mergeInspectedObjectsFromResponder:nextResponder seenControllers:seenControllers];
    }
}

- (void)_getInspectedObjects;
{
    static BOOL isFloating = YES;
    NSWindow *window = lastWindowAskedToInspect;
    
    // Don't float over non-document windows, unless the window in question is already at a higher level.
    // For example, the Quick Entry panel in OmniFocus -- calling -orderFront: ends up screwing up its exclusive activation support.  <bug://bugs/41806> (Calling up QE shows OF window [Quick Entry])
    
    NSWindowController *windowController = nil;
    if ([[window delegate] isKindOfClass:[NSWindowController class]])
	windowController = (NSWindowController *)[window delegate];
    
    BOOL hasDocument = ([windowController document] != nil);
    
    BOOL shouldFloat = window == nil || [window level] > NSFloatingWindowLevel || hasDocument;
    if (isFloating != shouldFloat) {
        for (OIInspectorGroup *group in [OIInspectorGroup groups])
            [group setFloating:shouldFloat];
        isFloating = shouldFloat;
        
        if (!shouldFloat)
            [window orderFront:self];
    }

    // Clear the old inspection
    [inspectionSet release];
    inspectionSet = [[OIInspectionSet alloc] init];

    // Fill the inspection set across all inspectable controllers in the responder chain, starting from the 'oldest' (probably the app delegate) to 'newest' the first responder.  This allows responders that are 'closer' to the user to override inspection from 'further' responders.
    NSResponder *responder = [window firstResponder];
    if (!responder)
        responder = window;
    [self _mergeInspectedObjectsFromResponder:responder seenControllers:[NSMutableSet set]];
}

- (void)_recalculateInspectionSetIfVisible:(BOOL)onlyIfVisible updateInspectors:(BOOL)updateInspectors;
{
    registryFlags.isInspectionQueued = NO;

    // Don't calculate inspection set if it would be pointless
    if (onlyIfVisible && ![self hasVisibleInspector])
        return;
    
    [self _getInspectedObjects];
    if (updateInspectors)
        [self inspectionSetChanged];
}

- (void)_selectionMightHaveChangedNotification:(NSNotification *)notification;
{
    [self _inspectWindow:[NSApp mainWindow] queue:YES onlyIfVisible:YES updateInspectors:YES];
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
        [defaultNotificationCenter addObserver:self selector:@selector(_selectionMightHaveChangedNotification:) name:OIInspectorSelectionDidChangeNotification object:nil];
        
	// Listen for all window close notifications; this is easier than keeping track of subscribing only once if lastWindowAskedToInspect and lastMainWindowBeforeAppSwitch are the same but twice if they differ (but not if on is nil, etc).  There aren't a huge number of these notifications anyway.
	[defaultNotificationCenter addObserver:self selector:@selector(_windowWillClose:) name:NSWindowWillCloseNotification object:nil];

        registryFlags.isListeningForNotifications = YES;
        [self queueSelectorOnce:@selector(_loadConfigurations)];        
    }
    
    [self restoreInspectorGroups];
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

    [workspaceDefaults setObject:config forKey:@"_Configurations"];
    [OIInspectorGroup saveExistingGroups];
}

- (void)_loadConfigurations;
{
    NSDictionary *config = [workspaceDefaults objectForKey:@"_Configurations"];
    
    for (OIInspectorController *controller in inspectorControllers)
        if ([[controller inspector] respondsToSelector:@selector(loadConfiguration:)])
            [[controller inspector] loadConfiguration:[config objectForKey:[controller identifier]]];
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
