// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSData.h>
#import <stdio.h>

// Extra methods factored out into another category
#import <OmniFoundation/NSData-OFEncoding.h>
#import <OmniFoundation/NSData-OFCompression.h>
#import <OmniFoundation/NSData-OFSignature.h>
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniFoundation/OFFilterProcess.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface NSData (OFExtensions)

+ (NSData *)randomDataOfLength:(NSUInteger)byteCount;
// Returns a new autoreleased instance that contains the number of requested random bytes.

+ (NSData *)cryptographicRandomDataOfLength:(NSUInteger)byteCount;
// Similar to -randomDataOfKength:, but uses the CSPRNG from CommonCrypto

+ (NSData *)dataWithDecodedURLString:(NSString *)urlString;

- (NSUInteger)indexOfFirstNonZeroByte;
    // Returns the index of the first non-zero byte in the receiver, or NSNotFound if if all the bytes in the data are zero.

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically createDirectories:(BOOL)shouldCreateDirectories error:(NSError **)outError;
#endif

- (NSData *)dataByAppendingData:(NSData *)anotherData;
    // Returns the catenation of this NSData and the argument
    
- (BOOL)hasPrefix:(NSData *)data;
- (BOOL)containsData:(NSData *)data;

- (NSRange)rangeOfData:(NSData *)data /* __attribute__((deprecated("Use -rangeOfData:options:range: instead"))) */;
- (NSUInteger)indexOfBytes:(const void *)bytes length:(NSUInteger)patternLength;
- (NSUInteger)indexOfBytes:(const void *)patternBytes length:(NSUInteger)patternLength range:(NSRange)searchRange;

- (id __nullable)propertyList;
    // a cover for the CoreFoundation function call

@end

NS_ASSUME_NONNULL_END
