// Copyright 2009-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <Security/Security.h>
#import <OmniFoundation/OFDigestUtilities.h>

#define OF_ENABLE_CSSM 1

/*
 This file has a handful of trivial data-holders for CSSM / CDSA objects: service providers, keys, and cryptographic contexts.
 
 Objects have a reference to their module, allowing the caller to use normal ObjC memory management for the module reference.
 
 The MAC and Signature objects conform to some common protocols, allowing the caller to ignore some minor differences in the way they behave.
*/

#if OF_ENABLE_CSSM
NSString *OFStringFromCSSMReturn(CSSM_RETURN code);
BOOL OFErrorFromCSSMReturn(NSError **outError, CSSM_RETURN errcode, NSString *function);
NSArray *OFReadCertificatesFromFile(NSString *path, SecExternalFormat inputFormat_, NSError **outError);
NSData *OFGetAppleKeyDigest(const CSSM_KEY *pkey, CSSM_CC_HANDLE optionalContext, NSError **outError);
#endif
NSString *OFSummarizeTrustResult(SecTrustRef evaluationContext);
#if OF_ENABLE_CSSM
CFArrayRef OFCopyIdentitiesForAuthority(CFArrayRef keychains, CSSM_KEYUSE usage, CFTypeRef anchors, SecPolicyRef policy, NSError **outError);
#endif

#if OF_ENABLE_CSSM
@interface OFCDSAModule : NSObject
{
    CSSM_MODULE_HANDLE hdl;
    BOOL detachWhenDone;
}

+ (OFCDSAModule *)moduleWithGUID:(const CSSM_GUID *)auid type:(CSSM_SERVICE_TYPE)serviceType;
+ (OFCDSAModule *)appleCSP;

- initWithHandle:(CSSM_MODULE_HANDLE)aHandle detach:(BOOL)d;
- (CSSM_MODULE_HANDLE)handle;

@end

@interface OFCSSMKey : NSObject
{
    OFCDSAModule *csp;
    CSSM_KEY key;
    
    NSData *keyBlob;
    SecKeyRef keyReference;
    const CSSM_ACCESS_CREDENTIALS *credentials;
}

+ (OFCSSMKey *)keyFromCertificateData:(const CSSM_DATA *)cert library:(OFCDSAModule *)x509CL error:(NSError **)outError;
+ (OFCSSMKey *)keyFromKeyRef:(SecKeyRef)secKey error:(NSError **)outError;
- initWithCSP:(OFCDSAModule *)cryptographcServiceProvider;

@property (readonly, nonatomic) OFCDSAModule *csp;
@property (readonly, nonatomic) const CSSM_KEY *key;
@property (readwrite, assign) const CSSM_ACCESS_CREDENTIALS *credentials;

- (void)setKeyHeader:(const CSSM_KEYHEADER *)hdr data:(NSData *)blobContents;

@end

@interface OFCSSMCryptographicContext : NSObject
{
    OFCDSAModule *csp;
    CSSM_CC_HANDLE ccontext;
}

- initWithCSP:(OFCDSAModule *)cryptographcServiceProvider cc:(CSSM_CC_HANDLE)ctxt;

@property (readonly, nonatomic) OFCDSAModule *csp;
@property (readonly, nonatomic) CSSM_CC_HANDLE handle;

@end

@interface OFCSSMMacContext : OFCSSMCryptographicContext <OFDigestionContext>
{
    BOOL generating;
}

- (BOOL)verifyInit:(NSError **)outError;
- (BOOL)verifyFinal:(NSData *)digest error:(NSError **)outError;

- (BOOL)generateInit:(NSError **)outError;
- (NSData *)generateFinal:(NSError **)outError;

- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;

@end

@interface OFCSSMSignatureContext : OFCSSMCryptographicContext <OFDigestionContext>
{
    BOOL signing;
}

- (BOOL)verifyInit:(NSError **)outError;
- (BOOL)verifyFinal:(NSData *)digest error:(NSError **)outError;

- (BOOL)generateInit:(NSError **)outError;
- (NSData *)generateFinal:(NSError **)outError;

- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;

@end

@interface OFCSSMDigestContext : OFCSSMCryptographicContext <OFDigestionContext>
{
    NSData *result;
}

- (BOOL)verifyInit:(NSError **)outError;
- (BOOL)verifyFinal:(NSData *)digest error:(NSError **)outError; /* Digest may be nil */

- (BOOL)generateInit:(NSError **)outError;
- (NSData *)generateFinal:(NSError **)outError;

- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;

@property (readonly, nonatomic) NSData *result;

@end
#endif // OF_ENABLE_CSSM

