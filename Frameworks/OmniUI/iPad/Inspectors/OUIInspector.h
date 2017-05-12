// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <OmniUI/OUIInspectorDelegate.h>
#import <OmniUI/OUIInspectorUpdateReason.h>
#import <OmniAppKit/OATextAttributes.h>
#import <CoreGraphics/CGBase.h>
#import <OmniUI/OUINavigationController.h>

@class OUIStackedSlicesInspectorPane, OUIInspectorPane, OUIInspectorSlice, OUIBarButtonItem;
@class UIBarButtonItem, UINavigationController;

extern CGFloat OUIInspectorContentWidth;
extern const NSTimeInterval OUICrossFadeDuration;

extern NSString * const OUIInspectorWillBeginChangingInspectedObjectsNotification;
extern NSString * const OUIInspectorDidEndChangingInspectedObjectsNotification;
extern NSString * const OUIInspectorPopoverDidDismissNotification;

@interface OUIInspector : NSObject

+ (UIBarButtonItem *)inspectorBarButtonItemWithTarget:(id)target action:(SEL)action;
+ (UIBarButtonItem *)inspectorOUIBarButtonItemWithTarget:(id)target action:(SEL)action;

+ (UIColor *)backgroundColor;
+ (UIColor *)disabledLabelTextColor;
+ (UIColor *)labelTextColor;
+ (UIFont *)labelFont;
+ (UIColor *)valueTextColor;
+ (UIColor *)indirectValueTextColor; // This is the color for Value text that isn't actionable in-place. For instance, a value on a cell with a chevron for drilling down to a detail view.

// Defaults to making a OUIStackedSlicesInspectorPane if mainPane is nil (or if -init is called).
- initWithMainPane:(OUIInspectorPane *)mainPane height:(CGFloat)height;

+ (CGFloat)defaultInspectorContentWidth;
@property(nonatomic) CGFloat defaultInspectorContentWidth;

@property(readonly,nonatomic) OUIInspectorPane *mainPane;
@property(readonly,nonatomic) CGFloat height;
@property(assign,nonatomic) BOOL alwaysShowToolbar;
@property(nonatomic, weak) UIView *gesturePassThroughView;
@property(nonatomic) BOOL animatingPushOrPop;

@property(weak,nonatomic) id <OUIInspectorDelegate> delegate;

@property(nonatomic, strong, readonly) UINavigationController *navigationController;

// JCTODO: This implementation expects that the navigation controller is being presented. We won't be presented in the new world. Check to see if this is still needed.
@property(readonly,nonatomic,getter=isVisible) BOOL visible;

// JCTODO: BEGIN REMOVAL
//- (BOOL)inspectObjects:(NSArray *)objects withViewController:(UIViewController *)viewController useFullScreenOnHorizontalCompact:(BOOL)useFullScreenOnHorizontalCompact fromBarButtonItem:(UIBarButtonItem *)item NS_EXTENSION_UNAVAILABLE_IOS("Inspection is not available in extensions.");
//- (BOOL)inspectObjects:(NSArray *)objects withViewController:(UIViewController *)viewController fromBarButtonItem:(UIBarButtonItem *)item NS_EXTENSION_UNAVAILABLE_IOS("Inspection is not available in extensions.");
//- (BOOL)inspectObjects:(NSArray *)objects withViewController:(UIViewController *)viewController fromRect:(CGRect)rect inView:(UIView *)view useFullScreenOnHorizontalCompact:(BOOL)useFullScreenOnHorizontalCompact permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections NS_EXTENSION_UNAVAILABLE_IOS("Inspection is not available in extensions.");
//- (BOOL)inspectObjects:(NSArray *)objects withViewController:(UIViewController *)viewController fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections NS_EXTENSION_UNAVAILABLE_IOS("Inspection is not available in extensions.");
//
//
//- (void)redisplayInspectorForNewTraitCollection:(UITraitCollection *)traitsCollection NS_EXTENSION_UNAVAILABLE_IOS("Inspection is not available in extensions.");
//- (void)dismissImmediatelyIfVisible;
//- (void)dismiss;
//- (void)dismissAnimated:(BOOL)animated;
//- (void)updateInspectorWithTraitCollection:(UITraitCollection *)traitCollection;
// JCTODO: END REMOVAL

@property (nonatomic) BOOL useFullScreenOnHorizontalCompact;

// JCTODO: Inspector refactor.
- (void)updateInspectedObjects;

- (NSArray *)makeAvailableSlicesForStackedSlicesPane:(OUIStackedSlicesInspectorPane *)pane;

- (void)pushPane:(OUIInspectorPane *)pane inspectingObjects:(NSArray *)inspectedObjects animated:(BOOL)animated withPushTransition:(id <UIViewControllerAnimatedTransitioning>)pushTransition popTransition:(id <UIViewControllerAnimatedTransitioning>)popTransition;
- (void)pushPane:(OUIInspectorPane *)pane inspectingObjects:(NSArray *)inspectedObjects animated:(BOOL)animated;
- (void)pushPane:(OUIInspectorPane *)pane inspectingObjects:(NSArray *)inspectedObjects;
- (void)pushPane:(OUIInspectorPane *)pane; // clones the inspected objects of the current top pane
- (void)popToPane:(OUIInspectorPane *)pane;

/**
 Same as `(OUIInspectorPane *)self.navigationController.topViewController`.
 */
@property(readonly,nonatomic) OUIInspectorPane *topVisiblePane;

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason; // If you wrap edits in the will/did change methods below, this will be called automatically on the 'did'.
- (void)willBeginChangingInspectedObjects; // start of ui action
- (void)didEndChangingInspectedObjects;    // end of ui action

- (void)beginChangeGroup;  // start of intermideate event
- (void)endChangeGroup;    // end of intermediate event

// JCTODO: BEGIN REFACTOR - Presentation is moving to the MultiPaneController. Proably need some way for it to handle something like this.
@property (copy, nonatomic) void (^presentInspectorCompletion)(void);
@property (copy, nonatomic) void (^animationsToPerformAlongsidePresentation)(id<UIViewControllerTransitionCoordinatorContext> context);
@property (copy, nonatomic) void (^dismissInspectorCompletion)(void);
/// There are times were you can request an animated dismissal but are dismissed non-animated anyway. Most people expect these to get called even if we don't dismiss animated. These are now called during a transition coordinator if one exists or immediately after dimissal.
@property (copy, nonatomic) void (^animationsToPerformAlongsideDismissal)(id<UIViewControllerTransitionCoordinatorContext> context);
// JCTODO: END REFACTOR - Presentation is moving to the MultiPaneController. Proably need some way for it to handle something like this.

@end

@interface NSObject (OUIInspectable)
- (BOOL)shouldBeInspectedByInspectorSlice:(OUIInspectorSlice *)inspector protocol:(Protocol *)protocol;
@end

@class OAColor;
@protocol OUIColorInspection <NSObject>
- (OAColor *)colorForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setColor:(OAColor *)color fromInspectorSlice:(OUIInspectorSlice *)inspector undoManager:(NSUndoManager *)undoManager;
- (NSString *)preferenceKeyForInspectorSlice:(OUIInspectorSlice *)inspector;
@end

@class OAFontDescriptor;
@protocol OUIFontInspection <NSObject>
- (OAFontDescriptor *)fontDescriptorForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setFontDescriptor:(OAFontDescriptor *)fontDescriptor fromInspectorSlice:(OUIInspectorSlice *)inspector undoManager:(NSUndoManager *)undoManager;
- (CGFloat)fontSizeForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setFontSize:(CGFloat)fontSize fromInspectorSlice:(OUIInspectorSlice *)inspector;

- (OAUnderlineStyle)underlineStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setUnderlineStyle:(OAUnderlineStyle)underlineStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;

- (OAUnderlineStyle)strikethroughStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setStrikethroughStyle:(OAUnderlineStyle)strikethroughStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;

@end

@class NSParagraphStyle;
@protocol OUIParagraphInspection <NSObject>
- (NSParagraphStyle *)paragraphStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setParagraphStyle:(NSParagraphStyle *)paragraphStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;
@end


@interface OUIInspectorNavigationController : OUINavigationController

@property (nonatomic, weak) UIView *gesturePassThroughView;
@property BOOL willDismissInspector;

@end
