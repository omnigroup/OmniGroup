// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OmniUI/OUIInspectorDelegate.h>
#import <OmniUI/OUIInspectorUpdateReason.h>
#import <CoreGraphics/CGBase.h>
#import <CoreText/CTStringAttributes.h>

@class OUIStackedSlicesInspectorPane, OUIInspectorPane, OUIInspectorSlice, OUIInspectorPopoverController;
@class UIBarButtonItem, UINavigationController, UIPopoverController;

extern const CGFloat OUIInspectorContentWidth;

extern NSString * const OUIInspectorDidPresentNotification;

extern NSString * const OUIInspectorWillBeginChangingInspectedObjectsNotification;
extern NSString * const OUIInspectorDidEndChangingInspectedObjectsNotification;

@interface OUIInspector : OFObject
{
@private
    // We hold onto this in case we don't have a _navigationController to retain it on our behalf (if we have -isEmbededInOtherNavigationController subclassed to return YES).
    OUIInspectorPane *_mainPane;
    CGFloat _height;
    
    UINavigationController *_navigationController;
    OUIInspectorPopoverController *_popoverController;
    
    id <OUIInspectorDelegate> _nonretained_delegate;
    
    BOOL _isObservingNotifications;
    BOOL _keyboardShownWhilePopoverVisible;
}

+ (UIBarButtonItem *)inspectorBarButtonItemWithTarget:(id)target action:(SEL)action;

+ (UIColor *)disabledLabelTextColor;
+ (UIColor *)labelTextColor;
+ (UIFont *)labelFont;

// Defaults to making a OUIStackedSlicesInspectorPane if mainPane is nil (or if -init is called).
- initWithMainPane:(OUIInspectorPane *)mainPane height:(CGFloat)height;

@property(readonly,nonatomic) OUIInspectorPane *mainPane;
@property(readonly,nonatomic) CGFloat height;

@property(assign,nonatomic) id <OUIInspectorDelegate> delegate;

- (BOOL)isEmbededInOtherNavigationController; // Subclass to return YES if you intend to embed the inspector into a your own navigation controller (you might not yet have the navigation controller, though).
- (UINavigationController *)embeddingNavigationController; // Needed when pushing detail panes with -isEmbededInOtherNavigationController.

@property(readonly,nonatomic,getter=isVisible) BOOL visible;

- (BOOL)inspectObjects:(NSArray *)objects fromBarButtonItem:(UIBarButtonItem *)item;
- (BOOL)inspectObjects:(NSArray *)objects fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections;
- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason; // If you wrap edits in the will/did change methods below, this will be called automatically on the 'did'.
- (void)dismiss;
- (void)dismissAnimated:(BOOL)animated;

- (NSArray *)makeAvailableSlicesForStackedSlicesPane:(OUIStackedSlicesInspectorPane *)pane;

- (void)pushPane:(OUIInspectorPane *)pane inspectingObjects:(NSArray *)inspectedObjects animated:(BOOL)animated;
- (void)pushPane:(OUIInspectorPane *)pane inspectingObjects:(NSArray *)inspectedObjects;
- (void)pushPane:(OUIInspectorPane *)pane; // clones the inspected objects of the current top pane
@property(readonly,nonatomic) OUIInspectorPane *topVisiblePane;

- (void)willBeginChangingInspectedObjects; // start of ui action
- (void)didEndChangingInspectedObjects;    // end of ui action

- (void)beginChangeGroup;  // start of intermideate event
- (void)endChangeGroup;    // end of intermediate event

@end

@interface NSObject (OUIInspectable)
- (BOOL)shouldBeInspectedByInspectorSlice:(OUIInspectorSlice *)inspector protocol:(Protocol *)protocol;
@end

@class OQColor;
@protocol OUIColorInspection <NSObject>
- (OQColor *)colorForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setColor:(OQColor *)color fromInspectorSlice:(OUIInspectorSlice *)inspector;
- (NSString *)preferenceKeyForInspectorSlice:(OUIInspectorSlice *)inspector;
@end

@class OAFontDescriptor;
@protocol OUIFontInspection <NSObject>
- (OAFontDescriptor *)fontDescriptorForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setFontDescriptor:(OAFontDescriptor *)fontDescriptor fromInspectorSlice:(OUIInspectorSlice *)inspector;
- (CGFloat)fontSizeForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setFontSize:(CGFloat)fontSize fromInspectorSlice:(OUIInspectorSlice *)inspector;

- (CTUnderlineStyle)underlineStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setUnderlineStyle:(CTUnderlineStyle)underlineStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;

- (CTUnderlineStyle)strikethroughStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setStrikethroughStyle:(CTUnderlineStyle)strikethroughStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;

@end

@class OAParagraphStyle;
@protocol OUIParagraphInspection <NSObject>
- (OAParagraphStyle *)paragraphStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setParagraphStyle:(OAParagraphStyle *)paragraphStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;
@end


