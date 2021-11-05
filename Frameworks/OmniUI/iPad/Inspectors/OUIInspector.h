// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#import <OmniUI/OUIInspectorDelegate.h>
#import <OmniUI/OUIInspectorUpdateReason.h>
#import <OmniAppKit/OATextAttributes.h>
#import <CoreGraphics/CGBase.h>
#import <OmniBase/OBUtilities.h>

@class OUIInspectorPane;

#pragma mark - OUIInspectorPaneContaining
@protocol OUIInspectorPaneContaining <NSObject>

@property (nonatomic, strong, readonly) NSArray<OUIInspectorPane *> *panes;

- (void)popPaneAnimated:(BOOL)animated;

@end

@class OUIStackedSlicesInspectorPane, OUIInspectorPane, OUIInspectorSlice, OUIBarButtonItem;
@class UIBarButtonItem, UINavigationController;

extern const NSTimeInterval OUICrossFadeDuration;

extern NSString * const OUIInspectorWillBeginChangingInspectedObjectsNotification;
extern NSString * const OUIInspectorDidEndChangingInspectedObjectsNotification;

#pragma mark - OUIInspector
@interface OUIInspector : NSObject

+ (UIBarButtonItem *)inspectorBarButtonItemWithTarget:(id)target action:(SEL)action;
+ (UIBarButtonItem *)inspectorOUIBarButtonItemWithTarget:(id)target action:(SEL)action;

+ (UIColor *)backgroundColor;
+ (UIColor *)disabledLabelTextColor;
+ (UIColor *)placeholderTextColor;
+ (UIColor *)labelTextColor;
+ (UIColor *)headerTextColor;
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

@property(weak,nonatomic) id <OUIInspectorDelegate> delegate;

@property(nonatomic, strong, readonly) UIViewController<OUIInspectorPaneContaining> *viewController;

- (void)setShowDoneButton:(BOOL)shouldShow;



/// Updates the inspected objects if self.viewController.view is within the window bounds. This allows us to ignore updates if we're not currently visible.
- (void)updateInspectedObjects;
/// Forces the inspected objects to update, even if self.viewController.view is not currently visible.
- (void)forceUpdateInspectedObjects;

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

@end

#pragma mark - NSObject (OUIInspectable)
@interface NSObject (OUIInspectable)
- (BOOL)shouldBeInspectedByInspectorSlice:(OUIInspectorSlice *)inspector protocol:(Protocol *)protocol;
@end

#pragma mark - OUIColorInspection
@class OAColor;
@protocol OUIColorInspection <NSObject>
- (OAColor *)colorForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setColor:(OAColor *)color fromInspectorSlice:(OUIInspectorSlice *)inspector;
- (NSString *)preferenceKeyForInspectorSlice:(OUIInspectorSlice *)inspector;
@end

#pragma mark - OUIFontInspection
@class OAFontDescriptor;
@protocol OUIFontInspection <NSObject>
- (OAFontDescriptor *)fontDescriptorForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setFontDescriptor:(OAFontDescriptor *)fontDescriptor fromInspectorSlice:(OUIInspectorSlice *)inspector;
- (CGFloat)fontSizeForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setFontSize:(CGFloat)fontSize fromInspectorSlice:(OUIInspectorSlice *)inspector;

- (OAUnderlineStyle)underlineStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setUnderlineStyle:(OAUnderlineStyle)underlineStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;

- (OAUnderlineStyle)strikethroughStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setStrikethroughStyle:(OAUnderlineStyle)strikethroughStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;

@end

#pragma mark - OUIParagraphInspection
@class NSParagraphStyle;
@protocol OUIParagraphInspection <NSObject>
- (NSParagraphStyle *)paragraphStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setParagraphStyle:(NSParagraphStyle *)paragraphStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;
@end

@interface NSObject (OUIInspectorDeprecated)
- (void)setColor:(OAColor *)color fromInspectorSlice:(OUIInspectorSlice *)inspector undoManager:(NSUndoManager *)undoManager OB_DEPRECATED_ATTRIBUTE;
- (void)setFontDescriptor:(OAFontDescriptor *)fontDescriptor fromInspectorSlice:(OUIInspectorSlice *)inspector undoManager:(NSUndoManager *)undoManager OB_DEPRECATED_ATTRIBUTE;
@end

