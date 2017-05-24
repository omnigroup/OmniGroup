// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorPane.h>

@class OUIInspectorSlice;
@protocol OUIScrollNotifier;

NS_ASSUME_NONNULL_BEGIN

@interface OUIStackedSlicesInspectorPane : OUIInspectorPane

+ (instancetype)stackedSlicesPaneWithAvailableSlices:(OUIInspectorSlice *)slice, ... NS_REQUIRES_NIL_TERMINATION;

@property(nonatomic,assign) UIEdgeInsets sliceAlignmentInsets;
@property(nonatomic,copy,nullable) UIColor *sliceSeparatorColor;

- (nullable NSArray<OUIInspectorSlice *> *)makeAvailableSlices; // For subclasses (though the delegate hook can also be used)
@property(nonatomic,copy,nullable) NSArray<OUIInspectorSlice *> *availableSlices; // All the possible slices. Will get narrowed by applicability.

- (void)sliceSizeChanged:(OUIInspectorSlice *)slice;

// these two classes are here so that OG can get at them in a sub-class to avoid letting us control their viewHierarchy.
- (void)setSlices:(nullable NSArray<OUIInspectorSlice *> *)slices maintainViewHierarchy:(BOOL)maintainHierachy;
- (nullable NSArray<OUIInspectorSlice *> *)appropriateSlicesForInspectedObjects;
- (nullable NSArray<OUIInspectorSlice *> *)appropriateSlices:(nullable NSArray<OUIInspectorSlice *> *)availableSlices forInspectedObjects:(NSArray *)inspectedObjects;  // Called from appropriateSlicesForInspectedObjects to allow subclasses the chance to use a subset of objects/slices

// The default implementation just sets the value of the slices property.  OG will want to instead call setSlices:newSlices maintainViewHierarchy:NO.

- (void)setNeedsSliceLayout;
- (void)updateSlices;

- (BOOL)inspectorPaneOfClassHasAlreadyBeenPresented:(Class)paneClass;
- (BOOL)inspectorSliceOfClassHasAlreadyBeenPresented:(Class)sliceClass;

// The scrollview containing the slices. This is just self.view here, but can be overridden in subclasses if there needs to be more view hierarchy.
- (UIView *)contentView;

- (void)updateContentInsetsForKeyboard;

@property (nonatomic, assign) BOOL isAnimating;
@end

NS_ASSUME_NONNULL_END
