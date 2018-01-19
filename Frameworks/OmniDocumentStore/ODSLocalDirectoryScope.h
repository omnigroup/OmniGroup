// Copyright 2010-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDocumentStore/ODSScope.h>

typedef enum {
    ODSLocalDirectoryScopeNormal,
    ODSLocalDirectoryScopeTrash,
    ODSLocalDirectoryScopeTemplate,
} ODSLocalDirectoryScopeType ;


@interface ODSLocalDirectoryScope : ODSScope

@property (class, nonatomic, copy) NSString *localDocumentsDisplayName;

+ (NSURL *)userDocumentsDirectoryURL;
+ (NSURL *)trashDirectoryURL;
+ (NSURL *)templateDirectoryURL;

- (id)initWithDirectoryURL:(NSURL *)directoryURL scopeType:(ODSLocalDirectoryScopeType)scopeType documentStore:(ODSStore *)documentStore;

@property(nonatomic,readonly) NSURL *directoryURL;
@property(nonatomic,readonly) BOOL isTrash;
@property(nonatomic,readonly) BOOL isTemplate;

@end
