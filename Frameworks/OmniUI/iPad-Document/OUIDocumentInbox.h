// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

// The ~/Documents/Inbox folder is populated by UIDocumentInteractionController.

@class ODSFileItem, ODSScope;

@interface OUIDocumentInbox : NSObject

+ (void)cloneInboxItem:(NSURL *)inboxURL toScope:(ODSScope *)scope completionHandler:(void (^)(ODSFileItem *newFileItem, NSError *errorOrNil))completionHandler;
+ (BOOL)coordinatedRemoveItemAtURL:(NSURL *)URL error:(NSError **)outError;

@end
