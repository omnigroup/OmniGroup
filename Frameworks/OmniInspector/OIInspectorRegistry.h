// Copyright 2002-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <AppKit/NSNibDeclarations.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindowController.h>
#import <OmniAppKit/OAWindowCascade.h> // For the OAWindowCascadeDataSource protocol
#import <OmniFoundation/OFController.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray, NSMutableArray, NSMutableDictionary, NSSet, NSPredicate;
@class NSButton, NSTableView, NSTextField, NSWindow, NSWindowController, NSMenu, NSMenuItem;
@class OIInspectionSet, OIInspectorGroup, OIWorkspace;

@class OIInspector, OIInspectorController;

@protocol OIConcreteInspector;

@interface OIInspectorRegistry : NSObject <OAWindowCascadeDataSource, NSMenuItemValidation>

+ (OIInspectorRegistry *)inspectorRegistryForMainWindow;
+ (BOOL)allowsEmptyInspectorList;

- (void)tabShowHidePanels;
- (BOOL)showAllInspectors;
- (BOOL)hideAllInspectors;
- (void)toggleAllInspectors;

- (id)initWithDefaultInspectorControllerClass:(Class)controllerClass;
- (void)invalidate;

+ (OIInspectionSet *)newInspectionSetForResponder:(nullable NSResponder *)responder;
- (void)updateInspectorForWindow:(NSWindow *)window;
- (void)updateInspectionSetImmediatelyAndUnconditionallyForWindow:(NSWindow *)window;
- (void)clearInspectionSet;

- (BOOL)hasSingleInspector;

- (BOOL)hasVisibleInspector;
- (void)forceInspectorsVisible:(NSSet *)preferred;
- (void)loadWorkspace:(NSString *)name;

@property(readonly) Class defaultInspectorControllerClass;
@property (readonly) BOOL hasHiddenInspectors;

/// Creates a new OIInspectorController for the given OIInspector. This method is here so that it can be overridden by app-specific subclasses of OIInspectorRegistry. If the inspector already has a controller registered in this registry, this method will still create a new controller and return it, duplicating the inspector in the registry; it will never return an existing controller.
- (OIInspectorController *)controllerWithInspector:(OIInspector <OIConcreteInspector> *)inspector;

/// Finds an existing OIInspectorController for the given OIInspector's identifier. This method will never create a new controller, and returns nil if the identifier is not associated with an existing controller's inspector.
- (nullable OIInspectorController *)controllerWithIdentifier:(NSString *)anIdentifier;

- (void)revealEmbeddedInspectorFromMenuItem:(id)sender;

/// Return all the OIInspectorController instances registered with this registry.
@property (nonatomic, readonly) NSArray <OIInspectorController *> *controllers;
- (void)removeInspectorController:(OIInspectorController *)controller;

- (NSArray *)inspectedObjects;
- (NSArray *)copyObjectsInterestingToInspector:(OIInspector <OIConcreteInspector> *)anInspector;
- (NSArray *)copyObjectsSatisfyingPredicate:(NSPredicate *)predicate;
- (NSArray *)inspectedObjectsOfClass:(Class)aClass;

- (NSString *)inspectionIdentifierForCurrentInspectionSet;
- (OIInspectionSet *)inspectionSet;

- (void)configurationsChanged;

@property(nonatomic,strong) IBOutlet NSTableView *editWorkspaceTable;

@property(nonatomic,readonly) NSArray *existingGroups;
- (void)addExistingGroup:(OIInspectorGroup *)group;
- (void)removeExistingGroup:(OIInspectorGroup *)group;

- (void)clearAllGroups;
- (NSArray *)groups;
- (NSUInteger)groupCount;
- (NSArray *)visibleGroups;
- (NSArray *)visibleWindows;

- (NSMenu *)workspaceMenu;
- (NSMenuItem *)resetPanelsItem;

- (IBAction)saveWorkspace:(id)sender;
- (IBAction)saveWorkspaceConfirmed:(id)sender;
- (IBAction)editWorkspace:(id)sender;
- (IBAction)deleteWorkspace:(id)sender;
- (IBAction)addWorkspace:(id)sender;
- (IBAction)overwriteWorkspace:(id)sender;
- (IBAction)restoreWorkspace:(id)sender;
- (IBAction)deleteWithoutConfirmation:(id)sender;
- (IBAction)cancelWorkspacePanel:(id)sender;
- (IBAction)switchToWorkspace:(id)sender;
- (IBAction)showWorkspacesHelp:(id)sender;
- (void)switchToDefaultWorkspace;

- (void)restoreInspectorGroups; // called at app startup, defaults change, etc.
- (void)dynamicMenuPlaceholderSet;

- (float)inspectorWidth; // fixed width of inspector window content-views (not window frames)
- (NSPoint)adjustTopLeftDefaultPositioningPoint:(NSPoint)topLeft;  // point is given in screen coordinates

- (void)setLastWindowAskedToInspect:(nullable NSWindow *)aWindow;

@property (nonatomic, readonly) BOOL applicationDidFinishRestoringWindows;
- (void)addGroupToShowAfterWindowRestoration:(OIInspectorGroup *)group;

@end

// Declare the part of OFControllerStatusObserver that we implement, so we can require subclasses to call super.
@interface OIInspectorRegistry () <OFControllerStatusObserver>
- (void)controllerStartedRunning:(OFController *)controller NS_REQUIRES_SUPER;
@end

// In general, class methods in this category call through to their instance method counterparts on the shared registry
@interface OIInspectorRegistry (Compatibility)

+ (void)updateInspectorForWindow:(NSWindow *)window;
+ (void)updateInspectionSetImmediatelyAndUnconditionallyForWindow:(NSWindow *)window;
+ (void)clearInspectionSetForWindow:(NSWindow *)window;

@end

extern NSString * const OIInspectionSetChangedNotification;

@interface NSView (OIInspectorExtensions)
- (BOOL)isInsideInspector;
@end

/// Informal protocol for apps to provide support for multiple inspector registries. Your app delegate will probably want to implement both of the following methods to provide a mapping between windows and inspector registries (e.g. for differentiating between multiple embedded registries, or between a floating and an embedded registry). You may return nil from either method in the event that a registry has no associated window or vice versa.
@interface NSObject (OIInspectorRegistryApplicationDelegate)
/// Implement this method on your application delegate to support inspectors. Do not call super in your implementation. If the given window has no dedicated registry, your app may decide to either return an app-wide registry (e.g. for floating inspectors) or nil (e.g. for windows that should not be inspected at all).
- (nullable OIInspectorRegistry *)inspectorRegistryForWindow:(nullable NSWindow *)window;

/// Implement this method on your application delegate to support embedded inspectors. Do not call super in your implementation. Your app may decide to return either a window (indicating an embedded inspector registry) or nil (for floating inspectors).
- (nullable NSWindow *)windowForInspectorRegistry:(OIInspectorRegistry *)inspectorRegistry;

/// Implement this on your application delegate to prevent loading an inspector with a given identifier.
- (BOOL)shouldLoadInspectorWithIdentifier:(NSString *)identifier inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry;
@end

@interface NSWindowController (OIInspectorRegistryWindowControllerDelegate)
// Implement this method on the window controller of your embedded inspectors to do anything required to show the inspectors when the user has explicitly chosen one from the menubar
- (void)inspectorRegistryDidRevealEmbeddedInspectorFromMenuItem:(OIInspectorRegistry *)registry;

@end

NS_ASSUME_NONNULL_END
