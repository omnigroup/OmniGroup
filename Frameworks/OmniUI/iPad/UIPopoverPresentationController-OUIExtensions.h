// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIPopoverPresentationController.h>

NS_ASSUME_NONNULL_BEGIN

/**
  When presenting a popover form a bar button item, UIPopoverPresentationController implicitly adds all the views associated with UIBarButtonItem instances in the originating bar as passthrough views.

  This is generally not the behavior we want. Previously we've worked around this by clearing the passthrough views in the presentation completion block. This is mostly acceptable, but it leaves the bar button items with an enabled/tinted/tappable look, which is confusing.

  This category adds `managedBarButtonItems` to UIPopoverPresentationController. Set these before presenting your popover. They will be automatically disabled before the popover is presented, then re-enabled when it is dismissed.

  I've also filed an enhancement request that UIPopoverPresentationController stop making this decision for us, and give us more direct control:

  rdar://problem/21910299
*/

@interface UIPopoverPresentationController (OUIExtensions)

// N.B. This is a read-only hash table because UIBarButtonItem violates the contract of -isEqual:/-hash, so we cannot safely use NSSet. Instead, the implementation manages the creation and lifecycle of a pointer-semantics hash table to attempt to deduplicate items while avoiding problems with object uniquing for sets.
@property (nonatomic, readonly) NSHashTable *managedBarButtonItems;

- (void)setManagedBarButtonItemsFromArray:(NSArray<UIBarButtonItem *> *)barButtonItems;
- (void)clearManagedBarButtonItems;

- (void)addManagedBarButtonItems:(nullable NSArray<UIBarButtonItem *> *)barButtonItems;
- (void)addManagedBarButtonItemsObject:(UIBarButtonItem *)barButtonItem;

- (void)removeManagedBarButtonItems:(NSArray<UIBarButtonItem *> *)barButtonItems;
- (void)removeManagedBarButtonItemsObject:(UIBarButtonItem *)barButtonItem;

// Convenience Methods

- (void)addManagedBarButtonItemsFromNavigationController:(nullable UINavigationController *)navigationController;
- (void)addManagedBarButtonItemsFromNavigationItem:(nullable UINavigationItem *)navigationItem;
- (void)addManagedBarButtonItemsFromToolbar:(nullable UIToolbar *)toolbar;

@end

#pragma mark -

@interface UIBarButtonItem (OUIPopoverPresentationExtensions)

@property (nonatomic) BOOL OUI_enabledStateIsManagedByPopoverPresentationController;

@end

NS_ASSUME_NONNULL_END
