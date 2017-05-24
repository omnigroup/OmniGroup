// Copyright 2011-2015,2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDigestUtilities.h>
#import <OmniFoundation/OFErrors.h>

#import <CommonCrypto/CommonDigest.h>

RCS_ID("$Id$")

@implementation OFCCDigestContext
{
@protected
    NSData *result;
    unsigned int outputLength;
}

- init
{
    if ( (self = [super init]) ) {
        outputLength = [[self class] outputLength];
        return self;
    }
    return nil;
}

- (void)dealloc
{
    [result release];
    [super dealloc];
}

@synthesize result;

- (void)setOutputLength:(unsigned int)v;
{
    if (v < 1 || v > [[self class] outputLength])
        OBRejectInvalidCall(self, _cmd, @"Truncation length (%u) out of range", v);
    outputLength = v;
}
@synthesize outputLength;

- (BOOL)verifyInit:(NSError **)outError;
{
    return [self generateInit:outError];
}

- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (BOOL)verifyFinal:(NSData *)check error:(NSError **)outError;
{
    if (![self generateFinal:outError])
        return NO;
    
    if (check) {
        // NSLog(@"Checking digest %@ against computed %@", [check description], [result description]);
        if (![check isEqual:result]) {
            if (outError) {
                NSString *descr = [NSString stringWithFormat:@"%@ mismatch", NSStringFromClass([self class])];
                *outError = [NSError errorWithDomain:OFErrorDomain
                                                code:OFXMLSignatureValidationFailure
                                            userInfo:[NSDictionary dictionaryWithObject:descr forKey:NSLocalizedDescriptionKey]];
            }
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)generateInit:(NSError **)outError;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSData *)generateFinal:(NSError **)outError;
{
    OBRequestConcreteImplementation(self, _cmd);
}

+ (unsigned int)outputLength;
{
    OBRequestConcreteImplementation(self, _cmd);
}

@end


/* CommonCrypto's APIs define the length arg of _Update() to be 32 bits even on a 64-bit platform; deal with that here */
/* The extra logic gets optimized out by the compiler on machines where size_t can't exceed CC_LONG_MAX */
#define CC_LONG_MAX UINT32_MAX
#define CC_LONG_BLOCKSIZE ( CC_LONG_MAX & ~( UINT32_C(0xFF) ) )
#define DO_CC_UPDATE(alg, ctxp) do { if (length > CC_LONG_MAX) { CC_ ## alg ## _Update(ctxp, buffer, CC_LONG_BLOCKSIZE); buffer += CC_LONG_BLOCKSIZE; length -= CC_LONG_BLOCKSIZE; } else { CC_ ## alg ## _Update(ctxp, buffer, (CC_LONG)length); break; } } while(length > 0)


@implementation OFMD5DigestContext
{
    CC_MD5_CTX ctx;
}

+ (unsigned int)outputLength;
{
    return CC_MD5_DIGEST_LENGTH;
}

- (BOOL)generateInit:(NSError **)outError;
{
    if (result) {
        [result release];
        result = nil;
    }
    
    CC_MD5_Init(&ctx);
    return YES;
}

- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;
{
    DO_CC_UPDATE(MD5, &ctx);
    return YES;
}

- (NSData *)generateFinal:(NSError **)outError;
{
    unsigned char buf[CC_MD5_DIGEST_LENGTH];
    CC_MD5_Final(buf, &ctx);
    if (result)
        [result release];
    result = [[NSData alloc] initWithBytes:buf length:outputLength];
    return result;
}

@end

@implementation OFSHA1DigestContext
{
    CC_SHA1_CTX ctx;
}

+ (unsigned int)outputLength;
{
    return CC_SHA1_DIGEST_LENGTH;
}

- (BOOL)generateInit:(NSError **)outError;
{
    if (result) {
        [result release];
        result = nil;
    }
    
    CC_SHA1_Init(&ctx);
    return YES;
}

- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;
{
    DO_CC_UPDATE(SHA1, &ctx);
    return YES;
}

- (NSData *)generateFinal:(NSError **)outError;
{
    unsigned char buf[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(buf, &ctx);
    if (result)
        [result release];
    result = [[NSData alloc] initWithBytes:buf length:outputLength];
    return result;
}

@end

@implementation OFSHA256DigestContext
{
    CC_SHA256_CTX ctx;
}

+ (unsigned int)outputLength;
{
    return CC_SHA256_DIGEST_LENGTH;
}

- (BOOL)generateInit:(NSError **)outError;
{
    if (result) {
        [result release];
        result = nil;
    }
    
    CC_SHA256_Init(&ctx);
    return YES;
}

- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;
{
    DO_CC_UPDATE(SHA256, &ctx);
    return YES;
}

- (NSData *)generateFinal:(NSError **)outError;
{
    unsigned char buf[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(buf, &ctx);
    if (result)
        [result release];
    result = [[NSData alloc] initWithBytes:buf length:outputLength];
    return result;
}

@end

@implementation OFSHA512DigestContext
{
    CC_SHA512_CTX ctx;
}

+ (unsigned int)outputLength;
{
    return CC_SHA512_DIGEST_LENGTH;
}

- (BOOL)generateInit:(NSError **)outError;
{
    if (result) {
        [result release];
        result = nil;
    }
    
    CC_SHA512_Init(&ctx);
    return YES;
}

- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;
{
    DO_CC_UPDATE(SHA512, &ctx);
    return YES;
}

- (NSData *)generateFinal:(NSError **)outError;
{
    unsigned char buf[CC_SHA512_DIGEST_LENGTH];
    CC_SHA512_Final(buf, &ctx);
    if (result)
        [result release];
    result = [[NSData alloc] initWithBytes:buf length:outputLength];
    return result;
}

@end

