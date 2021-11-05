// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIBarButtonItem.h>

extern NSString * const OUIUndoPopoverWillShowNotification;

@class OUIToolbarButton;
@class OUIUndoBarButtonItem;

@protocol OUIUndoBarButtonItemTarget <NSObject>
- (void)undo:(id)sender;
- (void)redo:(id)sender;
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender; // in case the target is not a subclass of UIResponder (like with OUIDocumentAppController)
@optional
- (void)willPresentMenuForUndoRedo;
@end

@interface OUIUndoBarButtonItem : UIBarButtonItem

// Normally, OUIUndoBarButtonItem listens for any undo manager notifications and updates its state from its target in response.
// Call this method if something else changes that requires any visible undo buttons to update their state. (For example, UITextView doesn't log an undo in its private undo manager right away when editing text, so delegates need to call this to inform OUIUndoBarButtonItem that they return a different value from -canPerformAction:withSender:).
+ (void)updateState;

@property(nonatomic,weak) id <OUIUndoBarButtonItemTarget> undoBarButtonItemTarget;

@property(nonatomic,readonly) OUIToolbarButton *button;
@property(nonatomic) BOOL disabledTemporarily;
@property(nonatomic) BOOL useImageForNonCompact; // Otherwise it's @"Undo"

+ (BOOL)dismissUndoMenu;

- (void)updateButtonForCompact:(BOOL)isCompact;

@end

@interface UIViewController (OUIUndoBarButtonItemPresentation)
/*! Presents the undo menu for long-press gestures.
 *
 *  When the undo button is long-pressed, it sends -targetForAction:withSender: to the button's target, with this selector as the action argument. By default, this will result in the receiver returning itself if -canPerformAction:withSender: returns YES with the same selector argument. (If the button's target does not respond to -targetForAction:withSender:, it assumes that it would have returned self). It then sends -presentMenuForUndoBarButtonItem: to the result if it responds to that selector.
 *
 * Implement or override -targetForAction:withSender: in your button's target to specify a different receiver for -presentMenuForUndoBarButtonItem:.
 */
- (void)presentMenuForUndoBarButtonItem:(OUIUndoBarButtonItem *)barButtonItem;
@end

extern NSString *OUILocalizedStringUndo(void);
extern NSString *OUILocalizedStringRedo(void);
