// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUISingleDocumentAppController.h>

@interface OUISingleDocumentAppController ()
- (void)_closeDocumentAndStartConflictResolutionWithCompletionHandler:(void (^)(void))completionHandler;
- (void)_startConflictResolution:(OFSDocumentStoreFileItem *)fileItem;
- (void)_stopConflictResolutionWithCompletion:(void (^)(void))completion;
- (void)_setupCloud:(id)sender;
@end
