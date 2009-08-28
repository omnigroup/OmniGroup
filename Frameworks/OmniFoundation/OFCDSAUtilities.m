// Copyright 2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFCDSAUtilities.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import "NSMutableDictionary-OFExtensions.h"
#import <Security/Security.h>

RCS_ID("$Id$");

#pragma mark Utility functions

extern const char *cssmErrorString(CSSM_RETURN code) __attribute__((weak));  /* Apple RADAR #4356597 */
extern CFStringRef SecCopyErrorMessageString(OSStatus status, void *reserved) __attribute__((weak));

static const struct {
    int moduleBase;
    const char *moduleName;
} cssmModuleBases[] = {
    { CSSM_CSSM_BASE_ERROR, "CSSM" },
    { CSSM_CSP_BASE_ERROR, "CSP" },
    { CSSM_DL_BASE_ERROR, "DL" },
    { CSSM_CL_BASE_ERROR, "CL" },
    { CSSM_TP_BASE_ERROR, "TP" },
    { CSSM_KR_BASE_ERROR, "KR" },
    { CSSM_AC_BASE_ERROR, "AC" },
    { CSSM_MDS_BASE_ERROR, "MDS" },
    { 0, NULL }
};

NSString *OFStringFromCSSMReturn(CSSM_RETURN code)
{
    NSString *errorString;
    
    errorString = nil;
    
    if (cssmErrorString != NULL) {
        const char *errString = cssmErrorString(code);
        if (errString)
            errorString = [NSString stringWithCString:errString encoding:NSASCIIStringEncoding];
    }
    
    if (errorString == nil && SecCopyErrorMessageString != NULL) {
        CFStringRef errString = SecCopyErrorMessageString(code, NULL);
        if (errString)
            errorString = [(NSString *)errString autorelease];
    }
    
    if (errorString == nil)
        errorString = @"error";
    
    if (code >= CSSM_BASE_ERROR && code < (CSSM_BASE_ERROR + 0x10000)) {
        int base = CSSM_ERRBASE(code);
        int module;
        for(module = 0; cssmModuleBases[module].moduleName != NULL; module++) {
            if (base == cssmModuleBases[module].moduleBase) {
                return [NSString stringWithFormat:@"%@ (CSSM_%@_BASE+%d)", errorString, [NSString stringWithCString:cssmModuleBases[module].moduleName encoding:NSASCIIStringEncoding], code - cssmModuleBases[module].moduleBase];
            }
        }
    }
    
    return [NSString stringWithFormat:@"%@ (%d)", errorString, code];
}

BOOL OFErrorFromCSSMReturn(NSError **outError, CSSM_RETURN errcode, NSString *function)
{
    if (outError) {
        NSString *descr = OFStringFromCSSMReturn(errcode);
        if (function)
            descr = [NSString stringWithStrings:descr, @" in ", function, nil];
        
        *outError = [NSError errorWithDomain:@"com.omnigroup.OmniFoundation.CDSA" code:errcode userInfo:[NSDictionary dictionaryWithObject:descr forKey:NSLocalizedDescriptionKey]];
    }
    return NO; // Useless, but makes clang-analyze happy
}

static inline NSString *NSStringFromCSSMGUID(CSSM_GUID uid)
{
    /* Note that despite the presence of ints and shorts in the CSSM_GUID structure, it's actually a byte sequence: the ordering within Data1, for example, does not change depending on the host's byte order. */
    const uint8 *data1overlay = (void *)&(uid.Data1);
    const uint8 *data2overlay = (void *)&(uid.Data2);
    const uint8 *data3overlay = (void *)&(uid.Data3);
    return [NSString stringWithFormat:@"{%02x%02x%02x%02x-%02x%02x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x}",
            data1overlay[0], data1overlay[1], data1overlay[2], data1overlay[3],
            data2overlay[0], data2overlay[1], data3overlay[2], data3overlay[3],
            uid.Data4[0], uid.Data4[1], uid.Data4[2], uid.Data4[3], 
            uid.Data4[4], uid.Data4[5], uid.Data4[6], uid.Data4[7]];
}

#pragma mark Cryptographic Service Provider handle

@implementation OFCDSAModule

static void *cssmLibcMalloc(CSSM_SIZE size, void *allocref)
{
    return malloc(size);
}

static void cssmLibcFree (void *memblock, void *allocref)
{
    free(memblock);
}

static void *cssmLibcRealloc(void *memblock, CSSM_SIZE size, void *allocref)
{
    return realloc(memblock, size);
}

static void *cssmLibcCalloc(uint32 num, CSSM_SIZE size, void *allocref)
{
    return calloc(num, size);
}

static const CSSM_API_MEMORY_FUNCS libcMemoryFuncs = {
    cssmLibcMalloc, cssmLibcFree, cssmLibcRealloc, cssmLibcCalloc, NULL
};

static void *cssmCFMalloc(CSSM_SIZE size, void *allocref)
{
    return CFAllocatorAllocate((CFAllocatorRef)allocref, size, 0);
}

static void cssmCFFree (void *memblock, void *allocref)
{
    CFAllocatorDeallocate((CFAllocatorRef)allocref, memblock);
}

static void *cssmCFRealloc(void *memblock, CSSM_SIZE size, void *allocref)
{
    return CFAllocatorReallocate((CFAllocatorRef)allocref, memblock, size, 0);
}

static void *cssmCFCalloc(uint32 num, CSSM_SIZE size, void *allocref)
{
    void *memblock = CFAllocatorAllocate((CFAllocatorRef)allocref, num * size, 0);
    memset(memblock, 0, num * size);
    return memblock;
}

static const CSSM_API_MEMORY_FUNCS coreFoundationMemoryFuncsPrototype = {
    cssmCFMalloc, cssmCFFree, cssmCFRealloc, cssmCFCalloc, NULL
};

static const CSSM_VERSION callingApiVersion = {2,0};

+ moduleWithGUID:(const CSSM_GUID *)auid type:(CSSM_SERVICE_TYPE)serviceType
{
    CSSM_RETURN err;
    CSSM_MODULE_HANDLE handle;
    OFCDSAModule *result;
    NSString *where;
    
    handle = CSSM_INVALID_HANDLE;
    
    where = @"moduleWithGUID: ModuleAttach1";
    err = CSSM_ModuleAttach (auid,
                             &callingApiVersion, &libcMemoryFuncs,
                             0, serviceType,
                             0,
                             CSSM_KEY_HIERARCHY_NONE,
                             NULL, 0,
                             NULL,
                             &handle);
    
    if (err == CSSMERR_CSSM_MODULE_NOT_LOADED) {
        where = @"moduleWithGUID: ModuleLoad";
        err = CSSM_ModuleLoad(auid, CSSM_KEY_HIERARCHY_NONE, NULL, NULL);
        if (err == CSSM_OK) {
            where = @"moduleWithGUID: ModuleAttach2";
            err = CSSM_ModuleAttach (auid,
                                     &callingApiVersion, &libcMemoryFuncs,
                                     0, serviceType,
                                     0,
                                     CSSM_KEY_HIERARCHY_NONE,
                                     NULL, 0,
                                     NULL,
                                     &handle);
        }
    }
    
    if (err != CSSM_OK) {
        [NSException raise:@"CSSM Failure" format:@"%@ in %@", OFStringFromCSSMReturn(err), where];
    }
    if (handle == CSSM_INVALID_HANDLE)
        return nil;
    
    result = [[self alloc] initWithHandle:handle detach:YES];
    [result autorelease];
    
    // NSLog(@"Request %@ service 0x%x -> %@", NSStringFromCSSMGUID(*auid), serviceType, [result description]);
    
    return result;
}

+ (OFCDSAModule *)appleCSP;
{
    return [self moduleWithGUID:&gGuidAppleCSP type:CSSM_SERVICE_CSP];
}

- initWithHandle:(CSSM_MODULE_HANDLE)aHandle detach:(BOOL)shouldDetach;
{
    self = [super init];
    hdl = aHandle;
    detachWhenDone = shouldDetach;
    return self;
}

- (void)dealloc
{
    if (detachWhenDone) {
        // NSLog(@"(Detaching module handle %" PRIxPTR ")", (uintptr_t)hdl);
        CSSM_ModuleDetach(hdl);
    }
    [super dealloc];
}

- (CSSM_MODULE_HANDLE)handle
{
    return hdl;
}

- (NSString *)description
{
    CSSM_GUID uid;
    
    CSSM_GetModuleGUIDFromHandle(hdl, &uid);
    return NSStringFromCSSMGUID(uid);
}

@end

#pragma mark Key reference

@implementation OFCSSMKey

- initWithCSP:(OFCDSAModule *)cryptographicServiceProvider
{
    self = [super init];
    
    csp = [cryptographicServiceProvider retain];
    
    // Should already be zero, but wth.
    key.KeyHeader.HeaderVersion = 0;  // Not a valid header version; indicates an uninitialized buffer.
    
    return self;
}

- (void)dealloc
{
    [self setKeyHeader:NULL data:nil];
    [csp release];
    [super dealloc];
}

- (OFCDSAModule *)csp;
{
    return csp;
}

- (const CSSM_KEY *)key;
{
    OBINVARIANT(!(keyBlob && keyReference));
    return &key;
}

- (void)setKeyHeader:(const CSSM_KEYHEADER *)hdr data:(NSData *)blobContents;
{
    if (keyBlob != nil) {
        OBINVARIANT(key.KeyData.Data == [keyBlob bytes]);
        [keyBlob release];
        keyBlob = nil;
    } else if (keyReference != NULL) {
        CFRelease(keyReference);
        keyReference = NULL;
    } else if (key.KeyHeader.HeaderVersion != 0) {
        CSSM_RETURN err = CSSM_FreeKey([csp handle], NULL, &key, CSSM_FALSE);
        if (err) {
            NSLog(@"-[%@ %@]: CSSM_FreeKey: %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), OFStringFromCSSMReturn(err));
        }
    }
    key.KeyData.Data = NULL;
    key.KeyData.Length = 0;
    
    credentials = NULL;
    
    if (hdr == NULL) {
        bzero(&(key.KeyHeader), sizeof(key.KeyHeader));
        return;
    }
    
    key.KeyHeader = *hdr;
    if (blobContents) {
        keyBlob = [blobContents retain];
        key.KeyData.Data = (uint8_t *)[keyBlob bytes];
        key.KeyData.Length = [keyBlob length];
    } else {
        key.KeyData.Data = NULL;
        key.KeyData.Length = 0;
    }
}

- (void)setKeyReference:(SecKeyRef)keyRef;
{
    [self setKeyHeader:NULL data:nil];
    
    const CSSM_KEY *kcKeyBuffer = NULL;
    OSStatus err = SecKeyGetCSSMKey(keyRef, &kcKeyBuffer);
    if (err != noErr) {
        NSLog(@"-[%@ %@]: SecKeyGetCSSMKey() returns %d", OBShortObjectDescription(self), _cmd, (int)err);
        return;
    }
    if (kcKeyBuffer == NULL) {
        NSLog(@"-[%@ %@]: SecKeyGetCSSMKey() returns NULL", OBShortObjectDescription(self), _cmd);
        return;
    }
    
    /* Might be nicer to keep using the SecKeyRef's key buffer, but it shouldn't hurt to duplicate it here. (Any embedded pointers still point into the keychain's copy, of course.) */
    memcpy(&key, kcKeyBuffer, sizeof(key));
    keyReference = keyRef;
    CFRetain(keyReference);
}

@synthesize credentials;

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    
    [dict setIntValue:key.KeyHeader.HeaderVersion forKey:@"HeaderVersion"];
    if (key.KeyHeader.HeaderVersion == CSSM_KEYHEADER_VERSION) {
        if (memcmp(&(key.KeyHeader.CspId), "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0", 8))
            [dict setObject:NSStringFromCSSMGUID(key.KeyHeader.CspId) forKey:@"CspId"];
        [dict setIntValue:key.KeyHeader.BlobType forKey:@"BlobType"];
        [dict setIntValue:key.KeyHeader.Format forKey:@"Format"];
        [dict setIntValue:key.KeyHeader.AlgorithmId forKey:@"AlgorithmId"];
        if (keyBlob)
            [dict setObject:keyBlob forKey:@"blob"];
        if (keyReference) {
            CFStringRef descr = CFCopyDescription(keyReference);
            [dict setObject:(NSString *)descr forKey:@"keyReference"];
            CFRelease(descr);
        }
    }
    if (csp)
        [dict setObject:csp forKey:@"csp"];
    
    return dict;
}

+ (OFCSSMKey *)keyFromCertificateData:(const CSSM_DATA *)cert library:(OFCDSAModule *)x509CL error:(NSError **)outError;
{
    CSSM_KEY *parsedKey = NULL;
    CSSM_RETURN cok = CSSM_CL_CertGetKeyInfo([x509CL handle], cert, &parsedKey);
    if (cok != CSSM_OK) {
        OFErrorFromCSSMReturn(outError, cok, @"CSSM_CL_CertGetKeyInfo");
        return nil;
    }
    
    /* There's no specific function for releasing the buffer we just got: we're supposed to deallocate it ourselves using the memory management functions the cert library is using. We know that OFCDSAModule just uses the libc functions, so this is straightforward. Otherwise we could use CSSM_GetAPIMemoryFunctions(). */
    
    NSData *publicKeyBlob = [[NSData alloc] initWithBytesNoCopy:parsedKey->KeyData.Data length:parsedKey->KeyData.Length freeWhenDone:YES];
    OFCSSMKey *key = [[OFCSSMKey alloc] initWithCSP:nil];
    [key setKeyHeader:&(parsedKey->KeyHeader) data:publicKeyBlob];
    [publicKeyBlob release];
    free(parsedKey);
    
    return [key autorelease];
}

+ (OFCSSMKey *)keyFromKeyRef:(SecKeyRef)secKey error:(NSError **)outError;
{
    if (!secKey || CFGetTypeID(secKey) != SecKeyGetTypeID())
        OBRejectInvalidCall(self, _cmd, @"SecKeyRef %p is not a key reference", secKey);
    
    CSSM_CSP_HANDLE cspHandle = CSSM_INVALID_HANDLE;
    OSStatus err = SecKeyGetCSPHandle(secKey, &cspHandle);
    if (err != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
        return nil;
    }
    
    /* The handle is only guaranteed to be valid for as long as the key ref is. */
    OFCDSAModule *keyCSP = [[OFCDSAModule alloc] initWithHandle:cspHandle detach:NO];
    OFCSSMKey *key = [[self alloc] initWithCSP:keyCSP];
    [keyCSP release];
    
    [key setKeyReference:secKey];
    
    return [key autorelease];
}

@end

#pragma mark Cryptographic contexts of various sorts

static inline BOOL cssmCheckError(NSError **outError, CSSM_RETURN errcode, NSString *function)
{
    if (errcode == CSSM_OK)
        return YES;
    else {
        return OFErrorFromCSSMReturn(outError, errcode, function);
    }
}

@implementation OFCSSMCryptographicContext

- initWithCSP:(OFCDSAModule *)cryptographcServiceProvider cc:(CSSM_CC_HANDLE)ctxt;
{
    self = [super init];
    csp = [cryptographcServiceProvider retain];
    ccontext = ctxt;
    return self;
}

- (void)dealloc
{
    CSSM_DeleteContext(ccontext);
    ccontext = CSSM_INVALID_HANDLE;
    [csp release];
    [super dealloc];
}

@synthesize csp;
@synthesize handle = ccontext;

@end

@implementation OFCSSMMacContext

- (BOOL)verifyInit:(NSError **)outError;
{
    CSSM_RETURN err = CSSM_VerifyMacInit(ccontext);
    generating = NO;
    return cssmCheckError(outError, err, @"CSSM_VerifyMacInit");
}

- (BOOL)processBuffers:(const CSSM_DATA *)buffers count:(unsigned int)bufferCount error:(NSError **)outError;
{
    if (generating) {
        CSSM_RETURN err = CSSM_GenerateMacUpdate(ccontext, buffers, bufferCount);
        return cssmCheckError(outError, err, @"CSSM_GenerateMacUpdate");
    } else {
        CSSM_RETURN err = CSSM_VerifyMacUpdate(ccontext, buffers, bufferCount);
        return cssmCheckError(outError, err, @"CSSM_VerifyMacUpdate");
    }
}

- (BOOL)verifyFinal:(NSData *)check error:(NSError **)outError;
{
    OBPRECONDITION(!generating);
    
    CSSM_DATA buf;
    buf.Data = (void *)[check bytes];
    buf.Length = [check length];
    
    CSSM_RETURN err = CSSM_VerifyMacFinal(ccontext, &buf);
    return cssmCheckError(outError, err, @"CSSM_VerifyMacFinal");
}

- (BOOL)generateInit:(NSError **)outError;
{
    CSSM_RETURN err = CSSM_GenerateMacInit(ccontext);
    generating = YES;
    return cssmCheckError(outError, err, @"CSSM_GenerateMacInit");
}

- (NSData *)generateFinal:(NSError **)outError;
{
    OBPRECONDITION(generating);
    
    CSSM_DATA buf;
    
    buf.Data = NULL;
    buf.Length = 0;
    CSSM_RETURN err = CSSM_GenerateMacFinal(ccontext, &buf);
    if (!cssmCheckError(outError, err, @"CSSM_GenerateMacFinal")) {
        if (buf.Data)
            free(buf.Data);
        return nil;
    }
    
    NSData *result = [[NSData alloc] initWithBytesNoCopy:buf.Data length:buf.Length freeWhenDone:YES];
    [result autorelease];
    
    return result;
}

@end

@implementation OFCSSMSignatureContext

- (BOOL)verifyInit:(NSError **)outError;
{
    signing = NO;
    CSSM_RETURN err = CSSM_VerifyDataInit(ccontext);
    return cssmCheckError(outError, err, @"CSSM_VerifyDataInit");
}

- (BOOL)processBuffers:(const CSSM_DATA *)buffers count:(unsigned int)bufferCount error:(NSError **)outError;
{
    if (signing) {
        CSSM_RETURN err = CSSM_SignDataUpdate(ccontext, buffers, bufferCount);
        return cssmCheckError(outError, err, @"CSSM_SignDataUpdate");
    } else {
        CSSM_RETURN err = CSSM_VerifyDataUpdate(ccontext, buffers, bufferCount);
        return cssmCheckError(outError, err, @"CSSM_VerifyDataUpdate");
    }
}

- (BOOL)verifyFinal:(NSData *)check error:(NSError **)outError;
{
    CSSM_DATA buf;
    buf.Data = (void *)[check bytes];
    buf.Length = [check length];
    
    CSSM_RETURN err = CSSM_VerifyDataFinal(ccontext, &buf);
    return cssmCheckError(outError, err, @"CSSM_VerifyDataFinal");
}

- (BOOL)generateInit:(NSError **)outError;
{
    signing = YES;
    CSSM_RETURN err = CSSM_SignDataInit(ccontext);
    return cssmCheckError(outError, err, @"CSSM_SignDataInit");
}

- (NSData *)generateFinal:(NSError **)outError;
{
    CSSM_DATA buf;
    
    buf.Data = NULL;
    buf.Length = 0;
    
    CSSM_RETURN err = CSSM_SignDataFinal(ccontext, &buf);
    if (!cssmCheckError(outError, err, @"CSSM_SignDataFinal"))
        return nil;
    
    // Note: We're relying again here on knowing that the memory API callbacks passed to the module were the libc allocators.
    return [NSData dataWithBytesNoCopy:buf.Data length:buf.Length freeWhenDone:YES];
}

@end

@implementation OFCSSMDigestContext

- (void)dealloc
{
    [result release];
    [super dealloc];
}

@synthesize result;

- (BOOL)verifyInit:(NSError **)outError;
{
    CSSM_RETURN err = CSSM_DigestDataInit(ccontext);
    return cssmCheckError(outError, err, @"CSSM_DigestDataInit");
}

- (BOOL)processBuffers:(const CSSM_DATA *)buffers count:(unsigned int)bufferCount error:(NSError **)outError;
{
    CSSM_RETURN err = CSSM_DigestDataUpdate(ccontext, buffers, bufferCount);
    return cssmCheckError(outError, err, @"CSSM_DigestDataUpdate");
}

- (BOOL)verifyFinal:(NSData *)check error:(NSError **)outError;
{
    if (![self generateFinal:outError])
        return NO;
    
    if (check) {
        // NSLog(@"Checking digest %@ against computed %@", [check description], [result description]);
        if (![check isEqual:result]) {
            cssmCheckError(outError, CSSMERR_CSP_VERIFY_FAILED, @"CSSM_VerifyDataFinal/check");
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)generateInit:(NSError **)outError;
{
    if (result) {
        [result release];
        result = nil;
    }
    
    CSSM_RETURN err = CSSM_DigestDataInit(ccontext);
    return cssmCheckError(outError, err, @"CSSM_DigestDataInit");
}

- (NSData *)generateFinal:(NSError **)outError;
{
    CSSM_DATA buf;
    
    buf.Data = NULL;
    buf.Length = 0;
    CSSM_RETURN err = CSSM_DigestDataFinal(ccontext, &buf);
    if (!cssmCheckError(outError, err, @"CSSM_VerifyDataFinal")) {
        if (buf.Data)
            free(buf.Data);
        return nil;
    }
    
    if (result)
        [result release];
    result = [[NSData alloc] initWithBytesNoCopy:buf.Data length:buf.Length freeWhenDone:YES];
    
    return result;
}

@end

NSArray *OFReadCertificatesFromFile(NSString *path, SecExternalFormat inputFormat_, NSError **outError)
{
    NSData *pemFile = [[NSData alloc] initWithContentsOfFile:path options:0 error:outError];
    if (!pemFile)
        return nil;
    
    SecExternalFormat inputFormat;
    SecExternalItemType itemType;
    SecKeyImportExportParameters  keyParams = (SecKeyImportExportParameters){
        .version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION,
        .flags = 0,
        .passphrase = NULL,
        .alertTitle = NULL,
        .alertPrompt = NULL,
        .accessRef = NULL,
        .keyUsage = CSSM_KEYUSE_VERIFY,
        .keyAttributes = CSSM_KEYATTR_EXTRACTABLE | CSSM_KEYATTR_RETURN_DATA
    };
    CFArrayRef outItems;
    
    inputFormat = inputFormat_;
    itemType = kSecItemTypeCertificate;
    
    OSStatus err = SecKeychainItemImport((CFDataRef)pemFile, (CFStringRef)path,
                                         &inputFormat, &itemType, 0, &keyParams, NULL, &outItems);
    
    [pemFile release];
    
    if (err != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:[NSDictionary dictionaryWithObjectsAndKeys:path, NSFilePathErrorKey, @"SecKeychainItemImport", @"function", nil]];
        return nil;
    }
    
    
    if (!outItems)
        return [NSArray array];
    NSArray *nsRef = [[(id)outItems retain] autorelease];
    CFRelease(outItems);
    return nsRef;
}

NSData *OFGetAppleKeyDigest(const CSSM_KEY *pkey, CSSM_CC_HANDLE ccontext, NSError **outError)
{
    CSSM_RETURN cssmerr;
    BOOL freeContext;
    
    if (ccontext == CSSM_INVALID_HANDLE) {
        cssmerr = CSSM_CSP_CreatePassThroughContext([[OFCDSAModule appleCSP] handle], pkey, &ccontext);
        if(cssmerr != CSSM_OK) {
            OFErrorFromCSSMReturn(outError, cssmerr, @"CSSM_CSP_CreatePassThroughContext");
            return nil;
        }
        freeContext = YES;
    } else {
        freeContext = NO;
    }
    
    void *outBuf = NULL;
    cssmerr = CSSM_CSP_PassThrough(ccontext, CSSM_APPLECSP_KEYDIGEST, pkey, &outBuf);
    
    if (cssmerr != CSSM_OK) {
        OFErrorFromCSSMReturn(outError, cssmerr, @"CSSM_CSP_PassThrough(CSSM_APPLECSP_KEYDIGEST)");
        if (freeContext)
            CSSM_DeleteContext(ccontext);
        return nil;
    }
    
    /* Apple's documentation doesn't specify, but the result of the passthrough is actually a CSSM_DATA */
    
    /* This is documented to be a SHA-1 digest, which is 20 bytes long... */
    NSData *result = [NSData dataWithBytes:((CSSM_DATA_PTR)outBuf)->Data length:((CSSM_DATA_PTR)outBuf)->Length];
        
    free(((CSSM_DATA_PTR)outBuf)->Data);
    free(outBuf);

    if (freeContext)
        CSSM_DeleteContext(ccontext);

    return result;
}
