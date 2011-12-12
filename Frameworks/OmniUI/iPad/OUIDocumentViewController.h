// Copyright 2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@class OUIDocument;
@protocol OUIDocumentViewController <NSObject>
// Set after the view controller is returned from the subclass implementation of -[OUIDocument makeViewController] (which should _not_ set it). Cleared when the document is closed.
@property(nonatomic,assign) OUIDocument *document;

@optional

// As the document is opening, animation will be disabled in -didMoveToParentViewController:. This will be called after the animation to make the view controller the main view controller's inner view controller is totally done (and animation is enabled again). This can be used, for example, to start editing and have the keyboard animate out.
- (void)documentFinishedOpening;

- (void)documentDidOpenUndoGroup;
- (void)documentWillCloseUndoGroup;

// should commit any partial edits to be included in the save
- (void)documentWillSave;

@end
