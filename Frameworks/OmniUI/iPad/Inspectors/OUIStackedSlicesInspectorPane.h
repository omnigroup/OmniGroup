// Copyright 2010-2012 The Omni Group. All rights reserved.
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

@interface OUIStackedSlicesInspectorPane : OUIInspectorPane
{
@private
    NSArray *_availableSlices;
    NSArray *_slices;
    id<OUIScrollNotifier> _scrollNotifier;
    BOOL _isAnimating;
    BOOL _keyboardIsAppearing;
}

+ (instancetype)stackedSlicesPaneWithAvailableSlices:(OUIInspectorSlice *)slice, ... NS_REQUIRES_NIL_TERMINATION;

- (NSArray *)makeAvailableSlices; // For subclasses (though the delegate hook can also be used)
@property(nonatomic,copy) NSArray *availableSlices; // All the possible slices. Will get narrowed by applicability.

- (void)sliceSizeChanged:(OUIInspectorSlice *)slice;

// these two classes are here so that OG can get at them in a sub-class to avoid letting us control their viewHierarchy.
- (void)setSlices:(NSArray *)slices maintainViewHierarchy:(BOOL)maintainHierachy;
- (NSArray *)appropriateSlicesForInspectedObjects;

// The default implementation just sets the value of the slices property.  OG will want to instead call setSlices:newSlices maintainViewHierarchy:NO.
- (void)updateSlices;

@end
