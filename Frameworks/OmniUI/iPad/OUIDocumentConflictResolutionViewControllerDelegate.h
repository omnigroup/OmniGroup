// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OUIDocumentConflictResolutionViewController;
@class OFSDocumentStoreFileItem;

@protocol OUIDocumentConflictResolutionViewControllerDelegate <NSObject>
- (void)conflictResolutionCancelled:(OUIDocumentConflictResolutionViewController *)conflictResolution;
- (void)conflictResolutionFinished:(OUIDocumentConflictResolutionViewController *)conflictResolution;

// Info message displayed while resolving conflicts for the given file item.
- (NSString *)conflictResolutionPromptForFileItem:(OFSDocumentStoreFileItem *)fileItem;

@end

