// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


NS_ASSUME_NONNULL_BEGIN

// Configuration: You can define this to include RFC3211-style key wrapping support, and activate a unit test against a known message from the RFC. We don't use RFC3211 wrapping (we use RFC3394 wrapping), so by default it isn't included.
// #define WITH_RFC3211_KEY_WRAP 1

@protocol OFCMSKeySource

/* Performs key lookup for CMS decryption. The CMS machinery treats NSCocoaErrorDomain.NSUserCancelledError and OFErrorDomain.OFKeyNotAvailable specially. In general if the method isn't implemented, OFKeyNotAvailable is the right error to return. */

- (NSString * __nullable)promptForPasswordWithCount:(NSInteger)previousFailureCount error:(NSError **)outError;
- (NSArray * __nullable)asymmetricKeysForQuery:(CFDictionaryRef)searchPattern error:(NSError **)outError; /* Returns an array of SecCertificate or SecIdentity depending on the kSecClass search term. */

@end

/* Option flags for the various CMS functions. Mostly these select alternative algorithms. The default values are chosen to be reasonable for our document encryption use case. */
typedef NS_OPTIONS(NSUInteger, OFCMSOptions) {
    OFCMSOptionPreferCCM      = 0x0001,  // Use CCM mode instead of GCM if both are available
    OFCMSOptionWithoutAEAD    = 0x0002,  // Use CBC mode instead of either CCM or GCM
    OFCMSOptionPreferRFC3211  = 0x0010,  // Use RFC3211 key wrapping instead of RFC3394 AESWRAP
    
    OFCMSOptionCompress       = 0x0100,  // Compress content
    OFCMSOptionContentIsXML   = 0x0200,  // Content is XML
    OFCMSOptionFileIsOptional = 0x0400,  // A file in the file package can be removed without breaking the document
    OFCMSOptionStoreInMain    = 0x0800,  // It makes sense to combine this file into the main cms object (e.g. it is the main document XML or something that changes equally reliably)
};

NS_ASSUME_NONNULL_END

