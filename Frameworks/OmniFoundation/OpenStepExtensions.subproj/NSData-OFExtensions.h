// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSData.h>
#import <stdio.h>

@class NSArray, NSError, NSOutputStream;

// Extra methods factored out into another category
#import <OmniFoundation/NSData-OFEncoding.h>
#import <OmniFoundation/NSData-OFCompression.h>
#import <OmniFoundation/OFFilterProcess.h>

typedef struct OFQuotedPrintableMapping {
    char map[256];   // 256 entries, one for each octet value
    unsigned short translations[8];  // 8 is an arbitrary size; must be at least 2
} OFQuotedPrintableMapping;

@interface NSData (OFExtensions)

+ (NSData *)randomDataOfLength:(NSUInteger)byteCount;
// Returns a new autoreleased instance that contains the number of requested random bytes.

+ dataWithDecodedURLString:(NSString *)urlString;

// This is a generic implementation of quoted-printable-style encodings, used by methods elsewhere in OmniFoundation
- (NSString *)quotedPrintableStringWithMapping:(const OFQuotedPrintableMapping *)qpMap lengthHint:(unsigned)zeroIfNoHint;
- (NSUInteger)lengthOfQuotedPrintableStringWithMapping:(const OFQuotedPrintableMapping *)qpMap;

- (NSUInteger)indexOfFirstNonZeroByte;
    // Returns the index of the first non-zero byte in the receiver, or NSNotFound if if all the bytes in the data are zero.

- (NSData *)copySHA1Signature;
- (NSData *)sha1Signature;
    // Uses the SHA-1 algorithm to compute a signature for the receiver.

- (NSData *)sha256Signature;
    // Uses the SHA-256 algorithm to compute a signature for the receiver.

- (NSData *)md5Signature;
    // Computes an MD5 digest of the receiver and returns it. (Derived from the RSA Data Security, Inc. MD5 Message-Digest Algorithm.)

- (NSData *)signatureWithAlgorithm:(NSString *)algName;

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically createDirectories:(BOOL)shouldCreateDirectories error:(NSError **)outError;

- (NSData *)dataByAppendingData:(NSData *)anotherData;
    // Returns the catenation of this NSData and the argument
    
- (BOOL)hasPrefix:(NSData *)data;
- (BOOL)containsData:(NSData *)data;

- (NSRange)rangeOfData:(NSData *)data;
- (NSUInteger)indexOfBytes:(const void *)bytes length:(NSUInteger)patternLength;
- (NSUInteger)indexOfBytes:(const void *)patternBytes length:(NSUInteger)patternLength range:(NSRange)searchRange;

- propertyList;
    // a cover for the CoreFoundation function call

// UNIX filters
#if 0 // Supplanted by OFFilterProcess
- (NSData *)filterDataThroughCommandAtPath:(NSString *)commandPath withArguments:(NSArray *)arguments includeErrorsInOutput:(BOOL)includeErrorsInOutput errorStream:(NSOutputStream *)errorStream error:(NSError **)outError;
- (NSData *)filterDataThroughCommandAtPath:(NSString *)commandPath withArguments:(NSArray *)arguments includeErrorsInOutput:(BOOL)includeErrorsInOutput;
- (NSData *)filterDataThroughCommandAtPath:(NSString *)commandPath withArguments:(NSArray *)arguments;
#endif

@end
