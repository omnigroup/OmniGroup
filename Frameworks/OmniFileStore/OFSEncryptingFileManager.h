// Copyright 2014 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSFileManager.h>


#define NSURLAuthenticationMethodOFSEncryptingFileManager @"OFSEncryptingFileManager"

@interface OFSEncryptingFileManager : OFSFileManager <OFSConcreteFileManager>

- initWithFileManager:(OFSFileManager <OFSConcreteFileManager> *)underlyingFileManager keyStore:(NSData *)finfo error:(NSError **)outError;
- initWithFileManager:(OFSFileManager <OFSConcreteFileManager> *)underlyingFileManager error:(NSError **)outError NS_DESIGNATED_INITIALIZER ;

- (BOOL)resetKey:(NSError **)error;  // Sets the document key to a new, randomly generated value. This is only a useful operation when you're creating a new document--- any existing items will become inaccessible.
- (NSData *)keyStoreForPassword:(NSString *)pass error:(NSError **)outError;  // Given a user's chosen password, return the key-management blob that should be passed to -initWithFileManager:keyStore:error: in order to produce an encrypting file manager with the same document key as this one.

@end

