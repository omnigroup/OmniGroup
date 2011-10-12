// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIViewController.h>

@class OUIDocumentStore, OUIDocumentConflictResolutionViewController;

@protocol OUIDocumentConflictResolutionViewControllerDelegate <NSObject>
- (void)conflictResolutionCancelled:(OUIDocumentConflictResolutionViewController *)conflictResolution;
- (void)conflictResolutionFinished:(OUIDocumentConflictResolutionViewController *)conflictResolution;
@end

@interface OUIDocumentConflictResolutionViewController : OUIViewController

- initWithDocumentStore:(OUIDocumentStore *)documentStore fileURL:(NSURL *)fileURL delegate:(id <OUIDocumentConflictResolutionViewControllerDelegate>)delegate;

@property(nonatomic,readonly) NSURL *fileURL;
@property(nonatomic,readonly,assign) id <OUIDocumentConflictResolutionViewControllerDelegate> delegate;

@end
