// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import "OUIInspectorDelegate.h"
#import <CoreGraphics/CGBase.h>

@class OUIInspectorStack, OUIInspectorSlice, OUIInspectorDetailSlice;
@class UIBarButtonItem, UINavigationController, UIPopoverController;
@class NSSet;

extern const CGFloat OUIInspectorContentWidth;

extern NSString * const OUIInspectorDidPresentNotification;

extern NSString * const OUIInspectorWillBeginChangingInspectedObjectsNotification;
extern NSString * const OUIInspectorDidEndChangingInspectedObjectsNotification;

@interface OUIInspector : OFObject
{
@private
    OUIInspectorStack *_stack;
    UINavigationController *_navigationController;
    UIPopoverController *_popoverController;
    
    id <OUIInspectorDelegate> _nonretained_delegate;
    
    NSSet *_inspectedObjects;
    BOOL _isObservingNotifications;
    BOOL _shouldShowDismissButton;
}

+ (UIBarButtonItem *)inspectorBarButtonItemWithTarget:(id)target action:(SEL)action;

@property(assign,nonatomic) id <OUIInspectorDelegate> delegate;
@property(assign,nonatomic,readwrite,getter=hasDismissButton) BOOL hasDismissButton;

- (BOOL)isEmbededInOtherNavigationController; // If YES, this doesn't create a navigation or popover controller

- (BOOL)isVisible;
- (void)inspectObjects:(NSSet *)objects fromBarButtonItem:(UIBarButtonItem *)item;
- (void)inspectObjects:(NSSet *)objects fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections;
@property(readonly) NSSet *inspectedObjects;
- (void)updateInterfaceFromInspectedObjects;
- (void)dismiss;
- (void)dismissAnimated:(BOOL)animated;

- (void)pushDetailSlice:(OUIInspectorDetailSlice *)detail;
- (void)popDetailSlice;

// Call this from inspector slices/details when they change height
- (void)inspectorSizeChanged;

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
- (NSSet *)colorsForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setColor:(OQColor *)color fromInspectorSlice:(OUIInspectorSlice *)inspector;
- (NSString *)preferenceKeyForInspectorSlice:(OUIInspectorSlice *)inspector;
@end

@class OAFontDescriptor;
@protocol OUIFontInspection <NSObject>
- (OAFontDescriptor *)fontDescriptorForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setFontDescriptor:(OAFontDescriptor *)fontDescriptor fromInspectorSlice:(OUIInspectorSlice *)inspector;
- (CGFloat)fontSizeForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setFontSize:(CGFloat)fontSize fromInspectorSlice:(OUIInspectorSlice *)inspector;

#if 0
@optional  // TODO: Make this non-optional?
- (CTUnderlineStyle)underlineStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setUnderlineStyle:(CTUnderlineStyle)underlineStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;
#endif

@end

@class OAParagraphStyle;
@protocol OUIParagraphInspection <NSObject>
- (OAParagraphStyle *)paragraphStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
- (void)setParagraphStyle:(OAParagraphStyle *)fontDescriptor fromInspectorSlice:(OUIInspectorSlice *)inspector;
@end


