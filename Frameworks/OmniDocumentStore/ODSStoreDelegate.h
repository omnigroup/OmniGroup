// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBUtilities.h>

@class ODSStore, ODSScope, ODSFileItem, ODSFileItemEdit;

OB_DEPRECATED_ATTRIBUTE
@protocol ODSStoreDelegate <NSObject>

- (NSString *)documentStoreBaseNameForNewFiles:(ODSStore *)store OB_DEPRECATED_ATTRIBUTE;
- (NSString *)documentStoreBaseNameForNewTemplateFiles:(ODSStore *)store OB_DEPRECATED_ATTRIBUTE;

@optional

- (NSString *)documentStoreBaseNameForNewOtherFiles:(ODSStore *)store OB_DEPRECATED_ATTRIBUTE;

- (NSString *)documentStoreDocumentTypeForNewFiles:(ODSStore *)store OB_DEPRECATED_ATTRIBUTE;
- (NSString *)documentStoreDocumentTypeForNewTemplateFiles:(ODSStore *)store OB_DEPRECATED_ATTRIBUTE;
- (NSString *)documentStoreDocumentTypeForNewOtherFiles:(ODSStore *)store OB_DEPRECATED_ATTRIBUTE;

- (void)documentStore:(ODSStore *)store fileItem:(ODSFileItem *)fileItem willMoveToURL:(NSURL *)newURL OB_DEPRECATED_ATTRIBUTE;
- (void)documentStore:(ODSStore *)store willRemoveFileItemAtURL:(NSURL *)destinationURL OB_DEPRECATED_ATTRIBUTE;

@end
