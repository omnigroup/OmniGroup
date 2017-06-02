// Copyright 2015-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDocumentStore/ODSFileItem.h>

NS_ASSUME_NONNULL_BEGIN

@interface ODSFileItem (OUIDocumentExtensions)

/// Application-specific subclasses of ODSFileItem can subclass this to report the file type identifiers that are available for this file item. The argument `isFileExportToLocalDocuments` is YES only if we are doing a filesystem-based export (not send-to-app, etc) to the local iTunes accessible Documents folder. The default implementation returns nil, in which case the export interface will build a default set of types. A NSNull may be inserted into this array to represent "the current type".
- (nullable NSArray *)availableExportTypesForFileExportToLocalDocuments:(BOOL)isFileExportToLocalDocuments;

@end

NS_ASSUME_NONNULL_END
