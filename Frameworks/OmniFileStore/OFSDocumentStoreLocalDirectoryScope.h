// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSDocumentStoreScope.h>

@interface OFSDocumentStoreLocalDirectoryScope : OFSDocumentStoreScope

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (NSURL *)userDocumentsDirectoryURL;
+ (NSURL *)trashDirectoryURL;
#endif

- (id)initWithDirectoryURL:(NSURL *)directoryURL isTrash:(BOOL)isTrash documentStore:(OFSDocumentStore *)documentStore;

@property(nonatomic,readonly) NSURL *directoryURL;
@property(nonatomic,readonly) BOOL isTrash;

@end
