// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

// A helper class to mediate popovers for OUIUndoButton so that OmniFocus can use it without using OUIAppController.
//
// The default implementation calls through to OUIAppController.
// A default instance will be created on demand if -setSharedHelper: hasn't been called.

@interface OUIUndoButtonPopoverHelper : NSObject

+ (id)sharedPopoverHelper;
+ (void)setSharedPopoverHelper:(OUIUndoButtonPopoverHelper *)popoverHelper;

- (BOOL)presentPopover:(UIPopoverController *)popover fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
- (BOOL)presentPopover:(UIPopoverController *)popover fromBarButtonItem:(UIBarButtonItem *)item permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
- (void)dismissPopover:(UIPopoverController *)popover animated:(BOOL)animated;
- (void)dismissPopoverAnimated:(BOOL)animated;

@end
