// Copyright 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/Foundation.h>

/* These routines parse out interesting parts of some common DER/BER-encoded objects, which is especially useful on iOS where we can't rely on Security.framework to do it for us. */
int OFASN1CertificateExtractFields(NSData *cert, NSData **serialNumber, NSData **issuer, NSData **subject, NSData **subjectKeyInformation, void (^extensions_cb)(NSData *oid, BOOL critical, NSData *value));
BOOL OFASN1EnumerateAVAsInName(NSData *rdnseq, void (^callback)(NSData *a, NSData *v, unsigned ix, BOOL *stop));
NSString *OFASN1UnDERString(NSData *derString);
NSString *OFASN1DescribeOID(const unsigned char *bytes, size_t len); // Textual description for debugging
