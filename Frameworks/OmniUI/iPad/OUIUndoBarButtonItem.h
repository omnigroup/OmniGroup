// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIBarButtonItem.h>

extern NSString * const OUIUndoPopoverWillShowNotification;

@class OUIToolbarButton;
@class OUIUndoBarButtonItem;

@protocol OUIUndoBarButtonItemTarget <NSObject>
- (void)undo:(id)sender;
- (void)redo:(id)sender;
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender; // in case the target is not a subclass of UIResponder (like with OUIDocumentAppController)
@end

@protocol OUIUndoBarButtonItemDelegate <NSObject>
- (UIViewController *)viewControllerToPresentMenuForUndoBarButtonItem:(OUIUndoBarButtonItem *)undoBarButtonItem;
@end

@interface OUIUndoBarButtonItem : UIBarButtonItem

// These are monitored for undo/redo groups. The OUIUndoBarButtonItemTarget is expected to figure out which one should do the action.
- (void)addUndoManager:(NSUndoManager *)undoManager;
- (void)removeUndoManager:(NSUndoManager *)undoManager;
- (BOOL)hasUndoManagers;

// This will get called automatically when the added undo managers post notifications, but in some cases the target might change its answer to -canPerformAction:withSender: before this happens (for example, UITextView doesn't log an undo in its private undo manager right away when editing text).
- (void)updateState;

@property(nonatomic,weak) id <OUIUndoBarButtonItemTarget> undoBarButtonItemTarget;
@property (nonatomic, weak) id<OUIUndoBarButtonItemDelegate> delegate;

@property(nonatomic,readonly) OUIToolbarButton *button;

- (BOOL)dismissUndoMenu;

@end
