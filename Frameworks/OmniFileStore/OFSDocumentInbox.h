// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniFileStore/OFSFeatures.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

// The ~/Documents/Inbox folder is populated by UIDocumentInteractionController.

@class OFSDocumentStoreFileItem, OFSDocumentStoreScope;

@interface OFSDocumentInbox : NSObject

+ (void)cloneInboxItem:(NSURL *)inboxURL toScope:(OFSDocumentStoreScope *)scope completionHandler:(void (^)(OFSDocumentStoreFileItem *newFileItem, NSError *errorOrNil))completionHandler;
+ (BOOL)deleteInbox:(NSError **)outError;

@end

#endif
