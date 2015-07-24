// Copyright 2015 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIPopoverPresentationController.h>

/**
  When presenting a popover form a bar button item, UIPopoverPresentationController implicitly adds all the views associated with UIBarButtonItem instances in the originating bar as passthrough views.

  This is generally not the behavior we want. Previously we've worked around this by clearing the passthrough views in the presentation completion block. This is mostly acceptable, but it leaves the bar button items with an enabled/tinted/tappable look, which is confusing.

  This category adds `managedBarButtonItems` to UIPopoverPresentationController. Set these before presenting your popover. They will be automatically disabled before the popover is presented, then re-enabled when it is dismissed.

  I've also filed an enhancement request that UIPopoverPresentationController stop making this decision for us, and give us more direct control:

  rdar://problem/21910299
*/

@interface UIPopoverPresentationController (OUIExtensions)

@property (nonatomic, copy) NSSet *managedBarButtonItems;

- (void)addManagedBarButtonItems:(NSSet *)barButtonItems;
- (void)addManagedBarButtonItemsObject:(UIBarButtonItem *)barButtonItem;

- (void)removeManagedBarButtonItems:(NSSet *)barButtonItems;
- (void)removeManagedBarButtonItemsObject:(UIBarButtonItem *)barButtonItem;

// Convenience Methods

- (void)addManagedBarButtonItemsFromNavigationController:(UINavigationController *)navigationController;
- (void)addManagedBarButtonItemsFromNavigationItem:(UINavigationItem *)navigationItem;
- (void)addManagedBarButtonItemsFromToolbar:(UIToolbar *)toolbar;

@end
