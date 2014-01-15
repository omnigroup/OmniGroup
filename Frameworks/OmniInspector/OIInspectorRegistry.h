// Copyright 2002-2008, 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <AppKit/NSNibDeclarations.h>

@class NSArray, NSMutableArray, NSMutableDictionary, NSSet, NSPredicate;
@class NSButton, NSTableView, NSTextField, NSWindow, NSWindowController, NSMenu, NSMenuItem;
@class OIInspectionSet, OIInspectorGroup;

@class OIInspector, OIInspectorController;

#import <OmniAppKit/OAWindowCascade.h> // For the OAWindowCascadeDataSource protocol

@interface OIInspectorRegistry : NSObject <OAWindowCascadeDataSource>
{
    NSWindow *lastWindowAskedToInspect;
    NSWindow *lastMainWindowBeforeAppSwitch;

    OIInspectionSet *inspectionSet;
    
    NSMutableDictionary *workspaceDefaults;
    NSMutableArray *workspaces;
    NSMenu *workspaceMenu;
    NSTimer *configurationsChangedTimer;
    
    struct {
	unsigned int isInspectionQueued:1;
	unsigned int isListeningForNotifications:1;
    } registryFlags;
    
    NSPanel *_saveWorkspacePanel, *_editWorkspacePanel;
    IBOutlet NSTextField *newWorkspaceTextField;
    IBOutlet NSTableView *editWorkspaceTable;
    IBOutlet NSButtonCell *deleteWorkspaceButton;
    IBOutlet NSButton *restoreWorkspaceButton;
    IBOutlet NSButton *overwriteWorkspaceButton;
    IBOutlet NSButton *workspacesHelpButton;

    NSMutableArray *inspectorControllers;
    float inspectorWidth;
    NSString *_currentInspectionIdentifier;
    
@private 
    BOOL _applicationDidFinishRestoringWindows;	// for document based app on 10.7, this means that the app has loaded its documents
    NSMutableArray *_groupsToShowAfterWindowRestoration;
}

// API
+ (void)setInspectorDefaultsVersion:(NSString *)versionString;
+ (void)registerAdditionalPanel:(NSWindowController *)additionalController;
+ (OIInspectorRegistry *)sharedInspector;
+ (Class)sharedInspectorClass;
+ (BOOL)allowsEmptyInspectorList;
+ (void)tabShowHidePanels;
+ (BOOL)showAllInspectors;
+ (BOOL)hideAllInspectors;
+ (void)toggleAllInspectors;

- (void)updateInspectorForWindow:(NSWindow *)window;
- (void)updateInspectionSetImmediatelyAndUnconditionallyForWindow:(NSWindow *)window;
- (void)clearInspectionSet;

- (BOOL)hasSingleInspector;

- (BOOL)hasVisibleInspector;
- (void)forceInspectorsVisible:(NSSet *)preferred;

/// Creates a new OIInspectorController for the given OIInspector. This method is here so that it can be overridden by app-specific subclasses of OIInspectorRegistry. If the inspector already has a controller registered in this registry, this method will still create a new controller and return it, duplicating the inspector in the registry; it will never return an existing controller.
- (OIInspectorController *)controllerWithInspector:(OIInspector *)inspector;

/// Finds an existing OIInspectorController for the given OIInspector's identifier. This method will never create a new controller, and returns nil if the identifier is not associated with an existing controller's inspector.
- (OIInspectorController *)controllerWithIdentifier:(NSString *)anIdentifier;

/// Return all the OIInspectorController instances registered with this registry.
- (NSArray *)controllers;

- (NSArray *)inspectedObjects;
- (NSArray *)copyObjectsInterestingToInspector:(OIInspector *)anInspector;
- (NSArray *)copyObjectsSatisfyingPredicate:(NSPredicate *)predicate;
- (NSArray *)inspectedObjectsOfClass:(Class)aClass;

- (NSString *)inspectionIdentifierForCurrentInspectionSet;
- (OIInspectionSet *)inspectionSet;

- (void)configurationsChanged;

- (NSMutableDictionary *)workspaceDefaults;
- (void)defaultsDidChange;

- (NSMenu *)workspaceMenu;
- (NSMenuItem *)resetPanelsItem;

- (void)saveWorkspace:sender;
- (void)saveWorkspaceConfirmed:sender;
- (void)editWorkspace:sender;
- (void)deleteWorkspace:sender;
- (IBAction)addWorkspace:(id)sender;
- (IBAction)overwriteWorkspace:(id)sender;
- (IBAction)restoreWorkspace:(id)sender;
- (IBAction)deleteWithoutConfirmation:(id)sender;
- (void)cancelWorkspacePanel:sender;
- (void)switchToWorkspace:sender;
- (void)switchToDefault:sender;
- (IBAction)showWorkspacesHelp:(id)sender;

- (void)restoreInspectorGroups; // called at app startup, defaults change, etc.
- (void)dynamicMenuPlaceholderSet;

- (float)inspectorWidth; // fixed width of inspector window content-views (not window frames)
- (NSPoint)adjustTopLeftDefaultPositioningPoint:(NSPoint)topLeft;  // point is given in screen coordinates

- (void)setLastWindowAskedToInspect:(NSWindow *)aWindow;

@property (nonatomic, readonly) BOOL applicationDidFinishRestoringWindows;
- (void)addGroupToShowAfterWindowRestoration:(OIInspectorGroup *)group;

@end

// In general, class methods in this category call through to their instance method counterparts on the shared registry
@interface OIInspectorRegistry (Compatibility)

+ (void)updateInspector;
+ (void)updateInspectionSetImmediatelyAndUnconditionally;
+ (void)clearInspectionSet;

+ (OIInspectorController *)controllerWithInspector:(OIInspector *)inspector;

@end

extern NSString *OIInspectionSetChangedNotification;
extern NSString *OIWorkspacesHelpURLKey;

#import <AppKit/NSView.h>

@interface NSView (OIInspectorExtensions)
- (BOOL)isInsideInspector;
@end
