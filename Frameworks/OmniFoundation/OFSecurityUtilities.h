// Copyright 2009-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Security/Security.h>

#import <TargetConditionals.h>
#import <OmniBase/macros.h>

NS_ASSUME_NONNULL_BEGIN

/* The utilities in this file have two purposes: to make some common operations a little easier, and to paper over some of the gratuitous differences between the crypto APIs on MacOSX vs. iOS. */

/* It's often more convenient to represent these as a few integers than as CFTypeRefs. (We have the advantage here that we don't worry much about binary compatibility in OmniFoundation, so we can rearrange this enum if we feel like it.) We could use the convenient CSSM_ALGID_RSA etc. constants directly, but I worry that Apple will decide to deprecate those. For now, rename the ones we use. This enum also makes it clear that we're collapsing related algorithms into one, since all we want to represent is the kind of key, not a specific algorithm. */
enum OFKeyAlgorithm {
    ka_Failure    = -1,
#ifdef CSSMAPI
    ka_RSA        = CSSM_ALGID_RSA,
    ka_DH         = CSSM_ALGID_DH,
    ka_DSA        = CSSM_ALGID_DSA,
    ka_AES        = CSSM_ALGID_AES,
    ka_DES        = CSSM_ALGID_3DES,   /* DES, 3DES, etc. */
    ka_EC         = CSSM_ALGID_ECDH,   /* ECDSA, ECDH, etc. discrete logs over elliptic curves */
    ka_Other      = CSSM_ALGID_CUSTOM  /* Any valid algorithm not already in this enum */
#else
    ka_RSA        = 1,
    ka_DH,
    ka_DSA,
    ka_AES,
    ka_EC,
    ka_Other
#endif
};

#if TARGET_OS_IPHONE
typedef enum OFSecItemClass {
    kSecCertificateItemClass        = 1,
    kSecPublicKeyItemClass,
    kSecPrivateKeyItemClass,
    kSecSymmetricKeyItemClass
} OFSecItemClass;
#else
typedef SecItemClass OFSecItemClass;
#endif

/* These are the flags returned in *outKeyFlags */
#define kOFKeyUsageEncrypt     0x00000001
#define kOFKeyUsageDecrypt     0x00000002
#define kOFKeyUsageDerive      0x00000004
#define kOFKeyUsageSign        0x00000008
#define kOFKeyUsageVerify      0x00000010
#define kOFKeyUsageWrap        0x00000020
#define kOFKeyUsageUnwrap      0x00000040

#define kOFKeyUsagePermanent   0x00010000
#define kOFKeyUsageTemporary   0x00020000



/* These are PBKDF2 round counts for various devices, obtained from CCCalibratePBKDF() running on the specified models of hardware. The round count is the result when asked to give a 100-millisecond estimate. These can be used to choose round counts when we're producing something that will need to be interpreted on other machines as well. (For hashes only used on the local machine, we can just call CCCalibratePBKDF() ourselves.) */

/* iPod Touch 5 */
#define OF_PBKDF2_ROUNDS_SHA1_N78AP       4000
#define OF_PBKDF2_ROUNDS_SHA256_N78AP     2400

/* iPad Mini 1 */
#define OF_PBKDF2_ROUNDS_SHA1_P105AP      5000
#define OF_PBKDF2_ROUNDS_SHA256_P105AP    3000

/* iPad 4 */
#define OF_PBKDF2_ROUNDS_SHA1_P101AP     10000
#define OF_PBKDF2_ROUNDS_SHA256_P101AP    6000

/* These devices using the A7 have similar performance:
   iPhone 5S (N51AP)      17000 21000
   iPad Air (J71AP)       17000 21000
   iPadMini2 (J85AP)      17000 21000
*/
#define OF_PBKDF2_ROUNDS_SHA1_AppleA7    17000
#define OF_PBKDF2_ROUNDS_SHA256_AppleA7  21000

/* These devices using the A8 (at 1.4 GHz or so) have similar performance:
 iPhone 6  (N61AP)      20000 22000
 iPhone 6+ (N56AP)      21000 22000
 iPadMini4 (J97AP)      22000 25000
*/
#define OF_PBKDF2_ROUNDS_SHA1_AppleA8    20000
#define OF_PBKDF2_ROUNDS_SHA256_AppleA8  22000

/* The iPhone 6S+ and peers use the A9 at 1.85 GHz:
 Phone6S+ (N66AP)       30000 33000
 */
#define OF_PBKDF2_ROUNDS_SHA1_AppleA9    30000
#define OF_PBKDF2_ROUNDS_SHA256_AppleA9  33000

/* The iPad Pro uses the A9X at 2.2 GHz:
 iPadPro (J127AP)       40000 41000
 */
#define OF_PBKDF2_ROUNDS_SHA1_AppleA9X   40000
#define OF_PBKDF2_ROUNDS_SHA256_AppleA9X 41000

/* For programs that need to create PBKDF2-hashed passwords which might be verified on any device, we maintain/use this constant. As we increase our minimum supported OS version we should update this to point to more recent hardware. */
#define OF_REASONABLE_PBKDF2_ITERATIONS (OF_PBKDF2_ROUNDS_SHA256_P105AP * 4) // Half a second on slowest hardware; faster on newer hardware

/* Returns a multiline string describing the results of a trust evaluation, for debugging/logging purposes. */
extern NSString *OFSummarizeTrustResult(SecTrustRef evaluationContext);

/* Retrieving some commonly-needed attributes of key references. There are three different APIs to get this information, which work in different (but overlapping) circumstances and OS versions. This routine attempts to do the right thing and be easy to use.
 
 Output values may be NULL (and may reduce the amount of work done if they are).
 
 *outItemClass -> The key's class, kSec{Public,Private,Symmetric}KeyItemClass
 *outKeySize   -> The key's size, in bits. For discrete-log keys, this is the group size. Set to zero if it cannot be determined.
 *outKeyFlags  -> Flags describing a key's abilities/permissions.
 
 */
extern enum OFKeyAlgorithm OFSecKeyGetAlgorithm(SecKeyRef item, OFSecItemClass * __nullable outItemClass, unsigned int * __nullable outKeySize, uint32_t * __nullable outKeyFlags, NSError **err);

#if !TARGET_OS_IPHONE
/* For the special case of a reference to a key that's in a keychain, you can call this. (If you don't know if it's a keychain key, go ahead and call OFSecKeyGetAlgorithm(); it will use OFSecKeychainItemGetAlgorithm() if it has to. */
extern enum OFKeyAlgorithm OFSecKeychainItemGetAlgorithm(SecKeychainItemRef item, OFSecItemClass * __nullable outItemClass, unsigned int * __nullable outKeySize, uint32_t * __nullable outKeyFlags, NSError **err);
#endif

/* Simple textual description of a key, e.g. "RSA-1024". Okay for presentation in user interfaces. */
extern NSString *OFSecKeyAlgorithmDescription(enum OFKeyAlgorithm alg, unsigned int keySizeBits);

/* A description of a keychain item in -[NSObject shortDescription] format, e.g. "<SecKeyRef 0x123456: Public RSA-1024>" */
extern NSString *OFSecItemDescription(CFTypeRef __nullable item);

#if TARGET_OS_IPHONE
/* This function makes up for the lack of key export functionality on iOS. On OSX, you can use SecItemExport(kSecFormatOpenSSL,...) instead. The addToKeychain flag controls whether the private key ref is in the keychain on exit--- the public key is not stored in the keychain, just returned as data. */
BOOL OFSecKeyGeneratePairAndInfo(enum OFKeyAlgorithm keyType, int keyBits, BOOL addToKeychain, NSString * __nullable label, NSData * __autoreleasing __nullable *  __nonnull outSubjectPublicKeyInfo, SecKeyRef __nullable * __nonnull outPrivateKey, NSError * __autoreleasing __nullable * outError);
#endif

/* A low-level routine for generating a certificate signing request per PKCS#10 / RFC2314 / RFC2986. The caller is responsible for producing a correctly DER-formatted name, list of request attributes (see PKCS#9 / RFC2985 for values), and SubjectPublicKeyInfo structure (the pub key info can be generated using SecItemExport with format kSecFormatOpenSSL on OSX, or by OFSecKeyGeneratePairAndInfo() on iOS). The returned data is a DER-encoded CertificationRequest structure suitable for use in an application/pkcs10 message per RFC5967. */
NSData * __nullable OFGenerateCertificateRequest(NSData *derName, NSData *publicKeyInfo, SecKeyRef privateKey, NSArray<NSData *> *derAttributes, NSMutableString * __nullable log, NSError **outError);

/* Returns the certificate's issuer (as a DER-encoded name), serial number (as the contents of a DER-encoded integer, without the tag), and subject key identifier (as a NSData, but only if the cert has the relevant extension). */
BOOL OFSecCertificateGetIdentifiers(SecCertificateRef aCert,
                                    NSData * __autoreleasing __nullable *  __nullable outIssuer, NSData * __autoreleasing __nullable * __nullable outSerial, NSData * __autoreleasing __nullable *  __nullable outSKI);

/* Given an RSA private key in PKCS#1 format, returns a SecKeyRef containing it. Currently only available in debug builds. */
SecKeyRef __nullable OFSecCopyPrivateKeyFromPKCS1Data(NSData *bytes) CF_RETURNS_RETAINED;

#if TARGET_OS_IPHONE
/* Bizarrely, SecCertificateCopyPublicKey() doesn't exist on iOS. */
SecKeyRef __nullable OFSecCertificateCopyPublicKey(SecCertificateRef aCert, NSError **outError) CF_RETURNS_RETAINED;
#endif

/* This is internal to OmniFoundation */
struct OFNamedCurveInfo {
    const char *name;
    const char *urn;                      /* URN of this curve */
    const uint8_t *derOid;                /* DER-encoded OID of this curve (including tag+length) */
    unsigned short derOidLength;          /* Byte length of derOid */
    unsigned short generatorSize;         /* number of bits needed to represent a value in the key's field */
};
extern const struct OFNamedCurveInfo _OFEllipticCurveInfoTable[] OB_HIDDEN;


NS_ASSUME_NONNULL_END
