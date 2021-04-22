// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSScope.h>

typedef enum {
    ODSLocalDirectoryScopeNormal,
    ODSLocalDirectoryScopeTemplate,
} ODSLocalDirectoryScopeType ;


@interface ODSLocalDirectoryScope : ODSScope

+ (NSURL *)userDocumentsDirectoryURL;
+ (NSURL *)templateDirectoryURL;

- (id)initWithDirectoryURL:(NSURL *)directoryURL scopeType:(ODSLocalDirectoryScopeType)scopeType documentStore:(ODSStore *)documentStore;

@property(nonatomic,readonly) NSURL *directoryURL;
@property(nonatomic,readonly) BOOL isTemplate;

@end
