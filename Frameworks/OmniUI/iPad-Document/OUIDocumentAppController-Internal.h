// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUIDocument/OUIDocumentAppController.h>

@class OFXServerAccount;

@interface OUIDocumentAppController ()
- (void)_setupCloud:(id)sender;
- (void)_didAddSyncAccount:(OFXServerAccount *)account;
- (void)_selectScopeWithAccount:(OFXServerAccount *)account completionHandler:(void (^)(void))completionHandler;
@end
