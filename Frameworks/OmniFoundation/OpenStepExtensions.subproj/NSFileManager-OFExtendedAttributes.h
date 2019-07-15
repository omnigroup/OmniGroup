// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSFileManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSFileManager (OFExtendedAttributes)

/// Returns a set of the extended attribute names that exist on the file at <code>path</code>. If there are no extended attributes on the given item, returns an empty set; if an error is encountered, returns <code>nil</code>. Does not follow symlinks.
- (NSSet<NSString *> * _Nullable)listExtendedAttributesForItemAtPath:(NSString *)path error:(NSError **)outError;

/// Returns the value of the named extended attribute on the file at <code>path</code>. If the given extended attribute doesn't exist on the item, returns <code>nil</code>. Does not follow symlinks.
- (NSData * _Nullable)extendedAttribute:(NSString *)xattr forItemAtPath:(NSString *)path error:(NSError **)outError;

/// Sets the given data as the value for the named extended attribute on the file at <code>path</code>. Returns <code>YES</code> on success and <code>NO</code> on error. Callers may pass <code>nil</code> for the value data to clear the value of the named extended attribute.
- (BOOL)setExtendedAttribute:(NSString *)xattr data:(NSData * _Nullable)data forItemAtPath:(NSString *)path error:(NSError **)outError;

/// Removes the named extended attribute from the file at <code>path</code>. Returns <code>YES</code> on success and <code>NO</code> on error.
- (BOOL)removeExtendedAttribute:(NSString *)xattr forItemAtPath:(NSString *)path error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
