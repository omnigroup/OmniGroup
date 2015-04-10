// Copyright 2014 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSFileManager.h>

@class OFSDocumentKey;

@interface OFSEncryptingFileManager : OFSFileManager <OFSConcreteFileManager>

- initWithFileManager:(OFSFileManager <OFSConcreteFileManager> *)underlyingFileManager keyStore:(OFSDocumentKey *)keyStore error:(NSError **)outError NS_DESIGNATED_INITIALIZER ;

@property (readwrite, copy, nonatomic) NSString *maskedFileName;
@property (readonly, nonatomic) OFSDocumentKey *keyStore;

@end


