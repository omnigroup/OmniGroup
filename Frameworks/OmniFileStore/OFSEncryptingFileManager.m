// Copyright 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSEncryptingFileManager.h>

#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/OFSDocumentKey.h>
#import <OmniFileStore/Errors.h>
#import <OmniDAV/ODAVFileInfo.h>

#if (defined(MAC_OS_X_VERSION_10_10) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000)
#import <CommonCrypto/CommonRandom.h>
#endif

RCS_ID("$Id$");

OB_REQUIRE_ARC

/* For the bulk encryption of files, we append a short fixed-length header containing a magic number and the per-file crypto information (currently the IV; we may have per-file wrapped keys in the future). Currently we don't have any kind of MAC on the files--- the possibility of someone else modifying our files is not in our threat model--- and although we could add one (an HMAC, AEAD mode, or something) that will make random access to large files difficult unless we ignore it or build a Merkle tree or something. Random access to large files is necessary on the phone, where we can't necessarily map in a transaction file containing many large attachments. We'll probably want to add an integrity check before moving this feature out of STRAWMAN state. */
#define FMT_V0_2_MAGIC_LEN 30
static const char magic_ver0_0[FMT_V0_2_MAGIC_LEN] = "Encrypted: AES-CBC STRAWMAN-2\n";
#define FMT_V0_2_HEADERLEN  ( FMT_V0_2_MAGIC_LEN + 16 )


/* We could use the derived key to simply wrap the bulk encryption keys themselves instead of having an intermediate document key, but that would make it difficult for the user to change their password without re-writing every encrypted file in the wrapper. This way we can simply wrap the same document key with a new password-derived key. It also leaves open the possibility of using keys on smartcards, phone TPMs, or whatever, to decrypt the document key, possibly with asymmetric crypto for least-authority background operation, and all that fun stuff. */

static NSError *wrapCCError(CCCryptorStatus cerr, NSString *op)
{
    /* CCCryptorStatus is actually in the Carbon OSStatus error domain */
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:op forKey:@"function"];
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:userInfo];
}
/* Security.framework errors are also OSStatus error codes */
#define wrapSecError(e,o) wrapCCError(e,o)

static BOOL randomBytes(uint8_t *buffer, size_t bufferLength, NSError **outError)
{
#if (defined(MAC_OS_X_VERSION_10_10) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000)
    CCRNGStatus randomErr = CCRandomGenerateBytes(buffer, bufferLength);
    if (randomErr) {
        if (outError)
            *outError = wrapCCError(randomErr, @"CCRandomGenerateBytes");
        return NO;
    }
#else
    if (SecRandomCopyBytes(kSecRandomDefault, bufferLength, buffer) != 0) {
        /* Documentation says "check errno to find out the real error" but a look at the published source code shows that's not going to be very reliable */
        if (outError)
            *outError = wrapSecError(kCCRNGFailure, @"SecRandomCopyBytes");
        return NO;
    }
#endif
    
    return YES;
}

@implementation OFSEncryptingFileManager
{
    OFSFileManager <OFSConcreteFileManager> *underlying;
    OFSDocumentKey *keyManager;
}

- initWithFileManager:(OFSFileManager <OFSConcreteFileManager> *)underlyingFileManager keyStore:(OFSDocumentKey *)keyStore error:(NSError **)outError;
{
    if (!(self = [super initWithBaseURL:[underlyingFileManager baseURL] delegate:[underlyingFileManager delegate] error:outError]))
        return nil;
    
    underlying = underlyingFileManager;
    keyManager = keyStore;
    
    return self;
}

- (void)invalidate
{
    [underlying invalidate];
    underlying = nil;
    keyManager = nil;
    [super invalidate];
}

@synthesize keyStore = keyManager;

#pragma mark OFSConcreteFileManager

+ (BOOL)shouldHaveHostInURL;
{
    return NO;
}

- (ODAVFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;
{
    return [underlying fileInfoAtURL:url error:outError];
}

- (NSArray *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;
{
    return [underlying directoryContentsAtURL:url havingExtension:extension error:outError];
}

- (NSMutableArray *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections error:(NSError **)outError;
{
    return [underlying directoryContentsAtURL:url collectingRedirects:redirections error:outError];
}

static NSData *processData(CCCryptorRef cryptor, NSData *input, NSRange range, const void *prefix, size_t prefixLength, NSError **outError)
{
    CCCryptorStatus cerr;
    size_t maxOutputLength = CCCryptorGetOutputLength(cryptor, range.length, true);
    size_t actualOutputLength;
    void *outputBuffer = malloc(prefixLength + maxOutputLength);

    if (prefixLength) {
        memcpy(outputBuffer, prefix, prefixLength);
    }

    cerr = CCCryptorUpdate(cryptor, [input bytes] + range.location, range.length, outputBuffer + prefixLength, maxOutputLength, &actualOutputLength);
    if (cerr) {
        free(outputBuffer);
        if (outError)
            *outError = wrapCCError(cerr, @"CCCryptorUpdate");
        return nil;
    }

    size_t tailPartAvailable, tailPartActual;
    tailPartAvailable = maxOutputLength - actualOutputLength;
    tailPartActual = 0;
    cerr = CCCryptorFinal(cryptor, outputBuffer + prefixLength + actualOutputLength, tailPartAvailable, &tailPartActual);
    if (cerr) {
        free(outputBuffer);
        if (outError)
            *outError = wrapCCError(cerr, @"CCCryptorFinal");
        return nil;
    }

    return [NSData dataWithBytesNoCopy:outputBuffer length:prefixLength + actualOutputLength + tailPartActual freeWhenDone:YES];
}

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;
{
    NSData *encrypted = [underlying dataWithContentsOfURL:url error:outError];
    if (!encrypted)
        return nil;

    NSUInteger encryptedLength = [encrypted length];
    if (encryptedLength >= FMT_V0_2_HEADERLEN &&
        !memcmp([encrypted bytes], magic_ver0_0, FMT_V0_2_MAGIC_LEN)) {

        /* As Simple As Could Possibly Work: the magic is followed by the AES IV (16 bytes) */
        const char *iv = [encrypted bytes] + FMT_V0_2_MAGIC_LEN;
        CCCryptorRef cryptor = NULL;

        CCCryptorStatus cerr = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCBC, kCCAlgorithmAES, kCCOptionPKCS7Padding, iv, keyManager->_key, kCCKeySizeAES128, NULL, 0, 0, 0, &cryptor);
        if (cerr) {
            if (outError)
                *outError = wrapCCError(cerr, @"CCCryptorCreateWithMode");
            return nil;
        }

        NSData *result = processData(cryptor, encrypted, (NSRange){ .location = FMT_V0_2_HEADERLEN, .length = encryptedLength - FMT_V0_2_HEADERLEN }, NULL, 0, outError);
        CCCryptorRelease(cryptor);

        if (!result) {
            // Stack another error on top
            OFSError(outError, OFSEncryptionBadFormat, @"Could not decrypt file", nil);
            return nil;
        } else {
            return result;
        }

    } else {
        //OFSError(outError, OFSEncryptionBadFormat, @"Could not decrypt file", @"Unrecognized encryption header");
        //return nil;
        NSLog(@"Passing through non-encrypted file: %@", url);
        return encrypted;
    }
}

- (NSURL *)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;
{
    uint8_t header[FMT_V0_2_HEADERLEN];

    memcpy(header, magic_ver0_0, FMT_V0_2_MAGIC_LEN);

    if (!randomBytes(header + FMT_V0_2_MAGIC_LEN, kCCBlockSizeAES128, outError)) {
        return nil;
    }

    CCCryptorRef cryptor = NULL;
    CCCryptorStatus cerr = CCCryptorCreateWithMode(kCCEncrypt, kCCModeCBC, kCCAlgorithmAES, kCCOptionPKCS7Padding, header + FMT_V0_2_MAGIC_LEN, keyManager->_key, kCCKeySizeAES128, NULL, 0, 0, 0, &cryptor);
    if (cerr) {
        if (outError)
            *outError = wrapCCError(cerr, @"CCCryptorCreateWithMode");
        return nil;
    }

    NSData *encrypted = processData(cryptor, data, (NSRange){ .location = 0, .length = [data length] }, header, FMT_V0_2_HEADERLEN, outError);
    CCCryptorRelease(cryptor);

    if (!encrypted) {
        // Stack another error on top
        OFSError(outError, OFSEncryptionBadFormat, @"Could not encrypt file", nil);
        return nil;
    } else {
        return [underlying writeData:encrypted toURL:url atomically:atomically error:outError];
    }
}

- (NSURL *)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;
{
    return [underlying createDirectoryAtURL:url attributes:attributes error:outError];
}

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;
{
    return [underlying moveURL:sourceURL toURL:destURL error:outError];
}

- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;
{
    return [underlying deleteURL:url error:outError];
}

@end

