// Copyright 2015-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class ODSStore;
@class ODSFileItem;

@interface OUIDocumentExternalScopeManager : NSObject

- (instancetype)initWithDocumentStore:(ODSStore *)store NS_DESIGNATED_INITIALIZER;

- (void)importExternalDocumentFromURL:(NSURL *)url;
- (ODSFileItem *)fileItemFromExternalDocumentURL:(NSURL *)url;

- (BOOL)addRecentlyOpenedDocumentURL:(NSURL *)url;
- (NSArray <ODSFileItem *> *)recentlyOpenedFileItems;

@end
