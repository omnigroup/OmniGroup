// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

// The ~/Documents/Inbox folder is populated by UIDocumentInteractionController.

@interface OUIDocumentInbox : NSObject

+ (void)takeInboxItem:(NSURL *)inboxURL completionHandler:(void (^)(NSURL *newFileURL, NSError *errorOrNil))completionHandler;

@end
