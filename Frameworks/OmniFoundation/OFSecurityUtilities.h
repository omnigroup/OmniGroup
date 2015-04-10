// Copyright 2009-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Security/Security.h>
#import <TargetConditionals.h>
#import <OmniBase/macros.h>

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

/* Returns a multiline string describing the results of a trust evaluation, for debugging/logging purposes. */
extern NSString *OFSummarizeTrustResult(SecTrustRef evaluationContext);

/* Retrieving some commonly-needed attributes of key references. There are three different APIs to get this information, which work in different (but overlapping) circumstances and OS versions. This routine attempts to do the right thing and be easy to use.
 
 Output values may be NULL (and may reduce the amount of work done if they are).
 
 *outItemClass -> The key's class, kSec{Public,Private,Symmetric}KeyItemClass
 *outKeySize   -> The key's size, in bits. For discrete-log keys, this is the group size. Set to zero if it cannot be determined.
 *outKeyFlags  -> Flags describing a key's abilities/permissions.
 
 */
extern enum OFKeyAlgorithm OFSecKeyGetAlgorithm(SecKeyRef item, OFSecItemClass *outItemClass, unsigned int *outKeySize, uint32_t *outKeyFlags, NSError **err);

#if !TARGET_OS_IPHONE
/* For the special case of a reference to a key that's in a keychain, you can call this. (If you don't know if it's a keychain key, go ahead and call OFSecKeyGetAlgorithm(); it will use OFSecKeychainItemGetAlgorithm() if it has to. */
extern enum OFKeyAlgorithm OFSecKeychainItemGetAlgorithm(SecKeychainItemRef item, OFSecItemClass *outItemClass, unsigned int *outKeySize, uint32_t *outKeyFlags, NSError **err);
#endif

/* Simple textual description of a key, e.g. "RSA-1024". Okay for presentation in user interfaces. */
extern NSString *OFSecKeyAlgorithmDescription(enum OFKeyAlgorithm alg, unsigned int keySizeBits);

/* A description of a keychain item in -[NSObject shortDescription] format, e.g. "<SecKeyRef 0x123456: Public RSA-1024>" */
extern NSString *OFSecItemDescription(CFTypeRef item);

/* This is internal to OmniFoundation */
struct OFNamedCurveInfo {
    const char *name;
    const char *urn;                      /* URN of this curve */
    const uint8_t *derOid;                /* DER-encoded OID of this curve (including tag+length) */
    unsigned short derOidLength;          /* Byte length of derOid */
    unsigned short generatorSize;         /* number of bits needed to represent a value in the key's field */
};
extern const struct OFNamedCurveInfo _OFEllipticCurveInfoTable[] OB_HIDDEN;

