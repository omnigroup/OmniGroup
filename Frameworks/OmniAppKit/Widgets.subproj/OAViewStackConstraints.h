// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSLayoutConstraint.h>
@class NSView, NSLayoutAnchor;

/// A non-view-hierarchy class that maintains the constraints between a set of views, some of which may be hidden.
/// This is useful for UI which has views which may or may not be present, but which should remain "stacked".
/// This is unlike an NSStackView in that it isn't an enclosing view, and it doesn't do hiding, etc.. (since hiding is controlled by the UI state or available features).
@interface OAViewStackConstraints : NSObject

- (instancetype)initWithViews:(NSArray <NSView *> *)views between:(NSLayoutAnchor *)before and:(NSLayoutAnchor *)after axis:(NSLayoutConstraintOrientation)axis;

@property (readonly,retain) NSArray <NSView *> *views;

// Setup. Spacings less than zero indicate that 'spacing' should be used instead; by default only 'spacing' is >0.
// Altering these properties after the first time you call -updateViewConstraints or -constraintFrom:to: will usually not work.
@property (readwrite,nonatomic) CGFloat emptySpacing;   /// The spacing between the edge anchors if all views are hidden
@property (readwrite,nonatomic) CGFloat firstSpacing;   /// The spacing from the edge to the first view
@property (readwrite,nonatomic) CGFloat spacing;        /// The spacing between adjacent views
@property (readwrite,nonatomic) CGFloat lastSpacing;    /// The spacing between the last view and the edge anchor
@property (readwrite,nonatomic) BOOL flipped;           /// Whether to swap anchor order. Defults to TRUE for vertical orientation, FALSE for horizontal.

/// Returns the constraint used when the given pair of views are adjacent, creating it if necessary. If a pair of views should have a non-default spacing or priority, it can be overridden by altering the constraint returned by this method.
- (NSLayoutConstraint *)constraintFrom:(NSView *)from to:(NSView *)to;

/// Creates, activates, and deactivates constraints.
- (void)updateViewConstraints;

/// Returns a copy of the set of constraints managed by this object (both active and inactive). This only includes constraints which have been created for some reason (by -updateViewConstraints or -constraintFrom:to:).
- (NSArray <NSLayoutConstraint *> *)constraints;

@end
