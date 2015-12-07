// Copyright 2014-2015 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSFileManager.h>
#import <OmniBase/OmniBase.h>

@class OFSDocumentKey;

NS_ASSUME_NONNULL_BEGIN

@interface OFSEncryptingFileManager : OFSFileManager <OFSConcreteFileManager>

- initWithFileManager:(OFSFileManager <OFSConcreteFileManager> *)underlyingFileManager keyStore:(OFSDocumentKey *)keyStore error:(OBNSErrorOutType)outError NS_DESIGNATED_INITIALIZER ;

@property (readwrite, copy, nonatomic, nullable) NSString *maskedFileName;
@property (readonly, nonatomic, nonnull) OFSDocumentKey *keyStore;

@end

NS_ASSUME_NONNULL_END
