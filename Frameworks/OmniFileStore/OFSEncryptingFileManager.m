// Copyright 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSEncryptingFileManager.h>

#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
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


/* Our key store data blob is a plist with the following keys */

#define KeyDerivationMethodKey              @"method"   /* How to derive the document key; see below */

/* Static method: the document key is simply stored in cleartext. Insecure obviously but useful for testing. */
#define KeyDerivationStatic                 @"static"
#define StaticKeyKey                        @"key"

/* Use PBKDF2 to derive a wrapping key, which is then used to wrap a random key using the RFC3394 aes128-wrap / AES-WRAP algorithm. The wrapped key is then stored. */
#define KeyDerivationPBKDF2_WRAP_AES        @"PBKDF2; aes128-wrap"
#define PBKDFRoundsKey                      @"rounds"
#define PBKDFSaltKey                        @"salt"
#define PBKDFPRFKey                         @"prf"
#define DocumentKeyKey                      @"key"

/* We could use the derived key to simply wrap the bulk encryption keys themselves instead of having an intermediate document key, but that would make it difficult for the user to change their password without re-writing every encrypted file in the wrapper. This way we can simply wrap the same document key with a new password-derived key. It also leaves open the possibility of using keys on smartcards, phone TPMs, or whatever, to decrypt the document key, possibly with asymmetric crypto for least-authority background operation, and all that fun stuff. */

@implementation OFSEncryptingFileManager
{
    OFSFileManager <OFSConcreteFileManager> *underlying;
    unsigned char localKey[kCCKeySizeAES128];
}

- initWithFileManager:(OFSFileManager <OFSConcreteFileManager> *)underlyingFileManager keyStore:(NSData *)storeData error:(NSError **)outError;
{
    NSError *error = NULL;
    NSDictionary *pl = [NSPropertyListSerialization propertyListWithData:storeData options:0 format:NULL error:&error];
    if (!pl || ![pl isKindOfClass:[NSDictionary class]]) {
        if (outError) {
            *outError = error;
            OFSError(outError, OFSEncryptionBadFormat, @"Could not decrypt file", @"Could not read encryption header");
        }
        return nil;
    }

    /* Looks superficially plausible. Go ahead and create our new instance, then discover the document key. */

    self = [self initWithFileManager:underlyingFileManager error:outError];
    if (!self)
        return nil;

    if (![self _deriveKey:pl error:outError])
        return nil;

    return nil;
}

- initWithFileManager:(OFSFileManager <OFSConcreteFileManager> *)underlyingFileManager error:(NSError **)outError;
{
    if (!(self = [super initWithBaseURL:[underlyingFileManager baseURL] delegate:[underlyingFileManager delegate] error:outError]))
        return nil;

    underlying = underlyingFileManager;
    memset(localKey, 0, sizeof(localKey));

    return self;
}

- (void)invalidate
{
    [underlying invalidate];
    underlying = nil;
    memset(localKey, 0, sizeof(localKey));
    [super invalidate];
}

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

static NSError *wrapCCError(CCCryptorStatus cerr, NSString *op)
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:op forKey:@"function"];
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:userInfo];
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

        CCCryptorStatus cerr = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCBC, kCCAlgorithmAES, kCCOptionPKCS7Padding, iv, localKey, kCCKeySizeAES128, NULL, 0, 0, 0, &cryptor);
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

    if (SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128, header + FMT_V0_2_MAGIC_LEN)) {
        /* Documentation says "check errno to find out the real error" but a look at the published source code shows that's not going to be very reliable */
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:kCCRNGFailure userInfo:nil];
        return nil;
    }

    CCCryptorRef cryptor = NULL;
    CCCryptorStatus cerr = CCCryptorCreateWithMode(kCCEncrypt, kCCModeCBC, kCCAlgorithmAES, kCCOptionPKCS7Padding, header + FMT_V0_2_MAGIC_LEN, localKey, kCCKeySizeAES128, NULL, 0, 0, 0, &cryptor);
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

#pragma mark Key management

static BOOL derive(uint8_t derivedKey[kCCKeySizeAES128], NSString *password, NSData *salt, unsigned int rounds, NSError **outError)
{
    /* TODO: A stringprep profile might be more appropriate here than simple NFC. Is there one that's been defined for unicode passwords? */
    NSData *passBytes = [[password precomposedStringWithCanonicalMapping] dataUsingEncoding:NSUTF8StringEncoding];
    if (!passBytes) {
        // Password itself was probably nil. Error out instead of crashing, though.
        if (outError)
            *outError = wrapCCError(-50, @"CCKeyDerivationPBKDF");
        return NO;
    }

    CCCryptorStatus cerr = CCKeyDerivationPBKDF(kCCPBKDF2, [passBytes bytes], [passBytes length],
                                               [salt bytes], [salt length],
                                               kCCPRFHmacAlgSHA1, rounds,
                                               derivedKey, kCCKeySizeAES128);

    if (cerr) {
        if (outError)
            *outError = wrapCCError(cerr, @"CCKeyDerivationPBKDF");
    }

    return YES;
}

static BOOL unwrap(uint8_t localKey[kCCKeySizeAES128], uint8_t wrappingKey[kCCKeySizeAES128], NSData *wrappedKey, NSError **outError)
{
    size_t unrapt = kCCKeySizeAES128;
    CCCryptorStatus cerr = CCSymmetricKeyUnwrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen,
                                                wrappingKey, kCCKeySizeAES128,
                                                [wrappedKey bytes], [wrappedKey length],
                                                localKey, &unrapt);
    memset(wrappingKey, 0, kCCKeySizeAES128);
    if (cerr) {
        if (outError)
            *outError = wrapCCError(cerr, @"CCSymmetricKeyUnwrap");
        return NO;
    } else {
        return YES;
    }

    /* Note that RFC3394-style key wrapping does effectively include a check field --- if we pass an incorrect wrapping key, or the wrapped key is bogus or something, it should fail. (I haven't tested Apple's implementation of this though.) */
}

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
        if (outError)
            *outError = wrapCCError(kCCRNGFailure, @"SecRandomCopyBytes");
        return NO;
    }
#endif

    return YES;
}

- (NSData *)keyStoreForPassword:(NSString *)pass error:(NSError **)outError;
{
    NSMutableDictionary *kminfo = [NSMutableDictionary dictionary];

    [kminfo setObject:KeyDerivationPBKDF2_WRAP_AES forKey:KeyDerivationMethodKey];

    /* TODO: Choose a round count dynamically using CCCalibratePBKDF()? The problem is we don't know if we're on one of the user's faster machines or one of their slower machines, nor how much tolerance the user has for slow unlocking on their slower machines. On my current 2.4GHz i7, asking for a 1-second derive time results in a round count of roughly 2560000. */
    unsigned roundCount = 1000000;
    unsigned saltLength = 30;

    [kminfo setUnsignedIntValue:roundCount forKey:PBKDFRoundsKey];

    NSMutableData *salt = [NSMutableData data];
    [salt setLength:saltLength];
    if (!randomBytes([salt mutableBytes], saltLength, outError))
        return nil;

    uint8_t passwordDerivedWrappingKey[kCCKeySizeAES128];
    if (!derive(passwordDerivedWrappingKey, pass, salt, roundCount, outError)) {
        return nil;
    }

    // Next, re-wrap our document key with the new password-derived key

    NSMutableData *wrappedKey = [NSMutableData data];
    size_t rapt = CCSymmetricWrappedSize(kCCWRAPAES, kCCKeySizeAES128);
    [wrappedKey setLength:rapt];
    CCCryptorStatus cerr = CCSymmetricKeyWrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen, passwordDerivedWrappingKey, kCCKeySizeAES128,
                                              localKey, kCCKeySizeAES128,
                                              [wrappedKey mutableBytes], &rapt);
    if (cerr) {
        if (outError)
            *outError = wrapCCError(cerr, @"CCSymmetricKeyWrap");
        return nil;
    }

    [kminfo setObject:wrappedKey forKey:DocumentKeyKey];
    [kminfo setObject:salt forKey:PBKDFSaltKey];

    /* Return an NSData blob with the information we'll need to recover the document key in the future. The caller will presumably store this blob in the underlying file manager or somewhere related, and hand it back to us via -initWithFileManager:keyStore:error:. */
    return [NSPropertyListSerialization dataWithPropertyList:kminfo format:NSPropertyListXMLFormat_v1_0 options:0 error:outError];
}

- (BOOL)_deriveKey:(NSDictionary *)docInfo error:(NSError **)outError;
{
    NSString *howto = [docInfo objectForKey:KeyDerivationMethodKey];
    if ([howto isEqualToString:KeyDerivationStatic]) {
        NSData *derivedKey = [docInfo objectForKey:StaticKeyKey];
        if ([derivedKey length] == kCCKeySizeAES128) {
            [derivedKey getBytes:localKey length:kCCKeySizeAES128];
            return YES;
        }
        /* Fall through to generic error return */
    } else if ([howto isEqualToString:KeyDerivationPBKDF2_WRAP_AES]) {
        unsigned pbkdfRounds = [docInfo unsignedIntForKey:PBKDFRoundsKey];
        if (!pbkdfRounds)
            goto fail_unrecognized;
        NSData *salt = [docInfo objectForKey:PBKDFSaltKey];
        if (![salt isKindOfClass:[NSData class]])
            goto fail_unrecognized;
        id prf = [docInfo objectForKey:PBKDFPRFKey];  // We don't currently support other PRFs, but check here in case we do in the future
        if (prf && ![prf isEqualToString:@"sha1"])
            goto fail_unrecognized;
        NSData *wrappedKey = [docInfo objectForKey:DocumentKeyKey];
        if (!wrappedKey || CCSymmetricUnwrappedSize(kCCWRAPAES, [wrappedKey length]) != kCCKeySizeAES128)
            goto fail_unrecognized;

        NSURLCredential *lastTry = nil;
        NSUInteger failureCount = 0;
        NSError *lastError = nil;
        NSURLProtectionSpace *spc = [[NSURLProtectionSpace alloc] initWithHost:nil port:0 protocol:nil realm:[[underlying baseURL] path] authenticationMethod:NSURLAuthenticationMethodOFSEncryptingFileManager];

        for(;;) {
            NSURLAuthenticationChallenge *req = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:spc
                                                                                           proposedCredential:lastTry previousFailureCount:failureCount failureResponse:nil error:lastError
                                                                                                       sender:nil];
            NSURLCredential *nextTry = [underlying.delegate fileManager:self findCredentialsForChallenge:req];
            if (!nextTry) {
                /* -fileManager:findCredentialsForChallenge: treats an unavailable password as an error--- it pops up a prompt but returns nil to us immediately. We unwind bac up to our caller, who will eventually call us again once the prompt is dismissed. (At least that's the theory.) */
                if (outError) {
                    NSMutableDictionary *i = [NSMutableDictionary dictionary];
                    [i setObject:[underlying baseURL] forKey:NSURLErrorFailingURLErrorKey];
                    if (lastError)
                        [i setObject:lastError forKey:NSUnderlyingErrorKey];
                    /* TODO: Is there a better domain+code to use here */
                    *outError = [NSError errorWithDomain:OFErrorDomain
                                                    code:OFKeyNotAvailable
                                                userInfo:i];
                }
                return NO;
            }

            lastError = nil;

            uint8_t wrappingKey[kCCKeySizeAES128];
            if (derive(wrappingKey, [nextTry password], salt, pbkdfRounds, &lastError) && unwrap(localKey, wrappingKey, wrappedKey, &lastError)) {
                /* If we reach this point, we have a localKey[] that is the result of a successful unwrap of the stored key value. */
                break;
            } else {
                /* Either PBKDF2 failed (probably won't ever happen?), or we got something that didn't pass the check value in unwrap() (wrong password). */
                lastTry = nextTry;
                failureCount ++;
            }
        }

        /* Falls through to here on success */
        return YES;
    }

fail_unrecognized:
    OFSError(outError, OFSEncryptionBadFormat, @"Could not decrypt file", @"Unrecognized settings in encryption header");
    return NO;
}

- (BOOL)resetKey:(NSError **)error;  // Sets the document key to a new, randomly generated value. This is only a useful operation when you're creating a new document--- any existing items will become inaccessible.
{
    memset(localKey, 0, sizeof(localKey));

    return randomBytes(localKey, kCCKeySizeAES128, error);
}

@end
