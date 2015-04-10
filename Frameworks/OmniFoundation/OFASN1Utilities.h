// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

/* These routines parse out interesting parts of some common DER/BER-encoded objects, which is especially useful on iOS where we can't rely on Security.framework to do it for us. */
int OFASN1CertificateExtractFields(NSData *cert, NSData **serialNumber, NSData **issuer, NSData **subject, NSData **subjectKeyInformation, void (^extensions_cb)(NSData *oid, BOOL critical, NSData *value));
BOOL OFASN1EnumerateAVAsInName(NSData *rdnseq, void (^callback)(NSData *a, NSData *v, unsigned ix, BOOL *stop));
BOOL OFASN1EnumerateAppStoreReceiptAttributes(NSData *payload, void (^callback)(int attributeType, int attributeVersion, NSRange valueRange));
#if TARGET_OS_IPHONE
NSData *OFPKCS7PluckContents(NSData *pkcs7);  /* (On OSX, use CMSDecoder) */
#endif

/* Converting between NSString and PKIX-profile DER */
NSString *OFASN1UnDERString(NSData *derString);
NSData *OFASN1EnDERString(NSString *str);

/* OIDs */
NSString *OFASN1DescribeOID(const unsigned char *bytes, size_t len); // Textual description for debugging
NSData *OFASN1OIDFromString(NSString *s);  // Return DER-encoded OID from a dotted-integers string - not really intended for user-supplied strings

/* Used for constructing DER-encoded objects */
void OFASN1AppendTagLength(NSMutableData *buffer, uint8_t tag, NSUInteger byteCount);
unsigned int OFASN1SizeOfTagLength(uint8_t tag, NSUInteger byteCount); // Number of bytes that OFASN1AppendTagLength() will produce
NSMutableData *OFASN1AppendStructure(NSMutableData *buffer, const char *fmt, ...);

