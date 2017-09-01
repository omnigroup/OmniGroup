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

- (instancetype)initWithDocumentStore:(ODSStore *)documentStore preferenceKey:(NSString *)preferenceKey NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithDocumentStore:(ODSStore *)store;

- (void)importExternalDocumentFromURL:(NSURL *)url;
- (void)linkExternalDocumentFromURL:(NSURL *)url;
- (ODSFileItem *)fileItemFromExternalDocumentURL:(NSURL *)url;


@end
