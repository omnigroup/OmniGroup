// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIBarButtonItem.h>

extern NSString * const OUIUndoPopoverWillShowNotification;

@class OUIUndoButtonController, OUIUndoButton;

@protocol OUIUndoBarButtonItemTarget
- (void)undo:(id)sender;
- (void)redo:(id)sender;
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender; // in case the target is not a subclass of UIResponder (like with OUISingleDocumentAppController)
@end

@interface OUIUndoBarButtonItem : UIBarButtonItem
{
@private
    NSUndoManager *_undoManager;
    OUIUndoButton *_undoButton;
    
    UITapGestureRecognizer *_tapRecoginizer;
    UILongPressGestureRecognizer *_longPressRecognizer;
    
    id <OUIUndoBarButtonItemTarget> _undoBarButtonItemTarget;
    OUIUndoButtonController *_buttonController;
    
    BOOL _canUndo, _canRedo;
}

@property(nonatomic,retain) NSUndoManager *undoManager;

@property(nonatomic,assign) id <OUIUndoBarButtonItemTarget> undoBarButtonItemTarget;

- (void)setNormalBackgroundImage:(UIImage *)image;
- (void)setHighlightedBackgroundImage:(UIImage *)image;
          
- (BOOL)dismissUndoMenu;

@end
