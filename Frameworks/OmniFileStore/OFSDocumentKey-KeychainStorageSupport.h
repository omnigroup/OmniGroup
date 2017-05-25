// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSDocumentKey.h>

@interface OFSDocumentKey (Keychain)

- (BOOL)deriveWithKeychainIdentifier:(NSString *)ident error:(NSError **)outError;
- (BOOL)storeWithKeychainIdentifier:(NSString *)ident displayName:(NSString *)displayName error:(NSError **)outError;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (BOOL)deleteAllEntriesWithError:(NSError **)outError;
#endif

@end
