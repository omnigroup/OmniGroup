// Copyright 1997-2008, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSData.h>

@interface NSData (OFSignature)

- (NSData *)copySHA1Signature;
- (NSData *)sha1Signature;
// Uses the SHA-1 algorithm to compute a signature for the receiver.

- (NSData *)sha256Signature;
// Uses the SHA-256 algorithm to compute a signature for the receiver.

- (NSData *)md5Signature;
// Computes an MD5 digest of the receiver and returns it. (Derived from the RSA Data Security, Inc. MD5 Message-Digest Algorithm.)

- (NSData *)signatureWithAlgorithm:(NSString *)algName;

@end
