// Copyright 2006-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class NSBundle, NSDictionary, NSPredicate; // Foundation
@class NSImage, NSMenuItem, NSView; // AppKit
@class OFEnumNameTable; // OmniFoundation
@class OIInspectorRegistry;
@class OIInspectorController;
@protocol OIConcreteInspector;

typedef NS_ENUM(NSUInteger, OIVisibilityState) {
    OIHiddenVisibilityState,
    OIVisibleVisibilityState,
    OIPinnedVisibilityState
};

typedef NS_ENUM(NSUInteger, OIInspectorInterfaceType) {
    OIInspectorInterfaceTypeFloating = 0, // default, window-based floating inspectors
    OIInspectorInterfaceTypeEmbedded, // no windows; suitable for sticking in e.g. a sidebar
};

@interface OIInspector : NSViewController

+ (OFEnumNameTable *)visibilityStateNameTable;

// This doesn't return `instancetype` since the type is specified in the dictionary.
+ (nullable __kindof OIInspector <OIConcreteInspector> *)inspectorWithDictionary:(NSDictionary *)dict inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry bundle:(nullable NSBundle *)sourceBundle;

- (nullable id)initWithDictionary:(NSDictionary *)dict inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry bundle:(nullable NSBundle *)sourceBundle;

@property (nullable, copy) NSString *identifier NS_UNAVAILABLE; // Owned by NSUserInterfaceItemIdentification

@property(nonatomic,readonly) NSString *inspectorIdentifier;
@property(nonatomic,readonly) OIVisibilityState defaultVisibilityState;

@property(nullable,nonatomic,readonly) NSString *shortcutKey;
@property(nonatomic,readonly) NSUInteger shortcutModifierFlags;

- (nullable NSImage *)imageNamed:(NSString *)imageName; // Finds the image in the app wrapper (if allowImagesFromApplication is true) or resourceBundle

@property(nonatomic,readonly) NSImage *image;
@property(nullable,nonatomic,readonly) NSImage *tabImage;
@property(nonatomic,readonly) NSBundle *resourceBundle;
@property(nonatomic,readonly) BOOL allowImagesFromApplication;
@property(nullable,nonatomic,readonly) NSString *inspectorImageName;
@property(nullable,nonatomic,readonly) NSString *inspectorTabImageName;

@property(nonatomic,readonly) NSString *displayName;
@property(nonatomic,readonly) CGFloat defaultHeaderHeight;
@property(nonatomic,readonly) CGFloat additionalHeaderHeight;

@property(nonatomic,weak) OIInspectorController *inspectorController;

@property(nonatomic,assign) NSUInteger defaultOrderingWithinGroup;

// TODO: Get rid of this
- (unsigned int)deprecatedDefaultDisplayGroupNumber;

- (NSMenuItem *)menuItemForTarget:(nullable id)target action:(SEL)action;
- (NSArray *)menuItemsForTarget:(nullable id)target action:(SEL)action;

- (void)setControlsEnabled:(BOOL)enabled;
- (void)setControlsEnabled:(BOOL)enabled inView:(NSView *)view;

- (BOOL)shouldBeUsedForObject:(id)object;
// This method is called by OITabbedInspector whenever the selection changes if the inspector is in auto-tab-select mode
@property(nonatomic,readonly,nullable) NSPredicate *shouldBeUsedForObjectPredicate;

// Subclasses should override this if they may need to do something in response to an inspector view programmatically resizing. They should also override this to pass it on to any inspectors they manage. (See OITabbedInspector) Inspectors which programmatically change the size of their inspectorView should then call this method on their inspectorController so it can notify the inspector chain. This allows an inspector view which contains a child inspector view to know to resize to accommodate changes in the size of that child.
- (void)inspectorDidResize:(OIInspector *)resizedInspector;

/// The interface type that this inspector would prefer the app to use. (Inspectors should support all interface types, but can have a weak preference for a certain type if that type suits its intended use better.)
@property(nonatomic,readonly) OIInspectorInterfaceType preferredInterfaceType;

@property (readonly) BOOL wantsHeader;
@property (readonly) BOOL isCollapsible;
@property (readonly) BOOL pinningDisabled;

@end

@protocol OIConcreteInspector
@property(nonatomic,readonly) NSPredicate *inspectedObjectsPredicate;
    // Return a predicate to filter the inspected objects down to what this inspector wants sent to its -inspectObjects: method

- (void)inspectObjects:(nullable NSArray *)objects;
    // This method is called whenever the selection changes

@optional // Customization

// If the inspector has any need to know its controller, it can implement this method
- (CGFloat)inspectorWillResizeToHeight:(CGFloat)height; // height of window content rect, excluding header button view
@property(nonatomic,readwrite) CGFloat inspectorMinimumHeight; // returns minimum height of window content rect
- (id)windowTitle;
// If implemented, this will be used instead of -inspectorName, to let the window title be dynamic. NSAttributedString or NSString are ok.

@property(nonatomic,readonly) NSDictionary *configuration;
- (void)loadConfiguration:(NSDictionary *)dict;
// These methods will be called to save and load any configuration information for the inspectors themselves on startup/shutdown and when workspaces are switched

- (BOOL)mayInspectObject:(id)anObject;

//
@property(nonatomic,assign) CGFloat inspectorWidth;

@end


@class OIInspectionSet;
@protocol OIInspectedObjectSelectionRelativeNames
- (nullable NSString *)inspector:(OIInspector *)inspector selectionRelativeNameForObject:(id)object amongObjects:(NSArray *)inspectedObjects inspectionSet:(OIInspectionSet *)inspectionSet;
@end

@interface OIInspector (OISelectionRelativeNames)
- (nullable NSString *)selectionRelativeNameForObject:(id)object amongObjects:(NSArray *)inspectedObjects;
@end

NS_ASSUME_NONNULL_END
