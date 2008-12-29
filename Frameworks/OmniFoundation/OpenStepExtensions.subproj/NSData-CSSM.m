// Copyright 2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFExtensions.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <Security/Security.h>

RCS_ID("$Id$");

@interface NSData (OFExtensions_CSSM)

- (NSData *)signatureWithAlgorithm:(UInt32)algorithm;

@end

#define OFCDSAExceptionName (@"OmniFoundation CDSA exception")
#define OFCDSAExceptionValueKey (@"CSSM_RETURN")

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

static NSString *stringForCSSMReturn(CSSM_RETURN code)
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

static NSException *cssmException(CSSM_RETURN code, const char *where)
{
    NSString *extraString = where? [NSString stringWithFormat:@" in %s", where] : @"";
    
    return [NSException exceptionWithName:OFCDSAExceptionName
                                   reason:[NSString stringWithFormat:@"CDSA error: %@%@", stringForCSSMReturn(code), extraString]
                                 userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:code] forKey:OFCDSAExceptionValueKey]];
}

static inline NSString *NSStringFromCSSMGUID(CSSM_GUID uid)
{
    return [NSString stringWithFormat:@"{%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x}",
        uid.Data1, uid.Data2, uid.Data3,
        uid.Data4[0], uid.Data4[1], uid.Data4[2], uid.Data4[3], 
        uid.Data4[4], uid.Data4[5], uid.Data4[6], uid.Data4[7]];
}

@interface OFCDSAModule : NSObject
{
    CSSM_MODULE_HANDLE hdl;
}

+ moduleWithGUID:(const CSSM_GUID *)auid type:(CSSM_SERVICE_TYPE)serviceType;

- initWithHandle:(CSSM_MODULE_HANDLE)aHandle;
- (CSSM_MODULE_HANDLE)handle;

@end

@implementation OFCDSAModule

static void *cssmLibcMalloc(uint32 size, void *allocref)
{
    return malloc(size);
}

static void cssmLibcFree (void *memblock, void *allocref)
{
    free(memblock);
}

static void *cssmLibcRealloc(void *memblock, uint32 size, void *allocref)
{
    return realloc(memblock, size);
}

static void *cssmLibcCalloc(uint32 num, uint32 size, void *allocref)
{
    return calloc(num, size);
}

static const CSSM_API_MEMORY_FUNCS libcMemoryFuncs = {
    cssmLibcMalloc, cssmLibcFree, cssmLibcRealloc, cssmLibcCalloc, NULL
};

static void *cssmCFMalloc(uint32 size, void *allocref)
{
    return CFAllocatorAllocate((CFAllocatorRef)allocref, size, 0);
}

static void cssmCFFree (void *memblock, void *allocref)
{
    CFAllocatorDeallocate((CFAllocatorRef)allocref, memblock);
}

static void *cssmCFRealloc(void *memblock, uint32 size, void *allocref)
{
    return CFAllocatorReallocate((CFAllocatorRef)allocref, memblock, size, 0);
}

static void *cssmCFCalloc(uint32 num, uint32 size, void *allocref)
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
    const char *where;
    
    handle = CSSM_INVALID_HANDLE;
    
    where = "moduleWithGUID: ModuleAttach1";
    err = CSSM_ModuleAttach (auid,
                             &callingApiVersion, &libcMemoryFuncs,
                             0, serviceType,
                             0,
                             CSSM_KEY_HIERARCHY_NONE,
                             NULL, 0,
                             NULL,
                             &handle);
    
    if (err == CSSMERR_CSSM_MODULE_NOT_LOADED) {
        where = "moduleWithGUID: ModuleLoad";
        err = CSSM_ModuleLoad(auid, CSSM_KEY_HIERARCHY_NONE, NULL, NULL);
        if (err == CSSM_OK) {
            where = "moduleWithGUID: ModuleAttach2";
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
    
    if (err != CSSM_OK)
        [cssmException(err, where) raise];
    if (handle == CSSM_INVALID_HANDLE)
        return nil;
    
    result = [[self alloc] initWithHandle:handle];
    [result autorelease];
    
    NSLog(@"Request %@ service 0x%x -> %@", NSStringFromCSSMGUID(*auid), serviceType, [result description]);
    
    return result;
}

- initWithHandle:(CSSM_MODULE_HANDLE)aHandle;
{
    self = [super init];
    hdl = aHandle;
    return self;
}

- (void)dealloc
{
    CSSM_ModuleDetach(hdl);
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

static OFCDSAModule *appleCSP(void)
{
    return [OFCDSAModule moduleWithGUID:&gGuidAppleCSP type:CSSM_SERVICE_CSP];
}

@implementation NSData (OFExtensions_CSSM)

- (NSData *)signatureWithAlgorithm:(CSSM_ALGORITHMS)algo csp:(CSSM_CSP_HANDLE)csp;
{
    CSSM_CC_HANDLE ctxt = CSSM_INVALID_HANDLE;
    CSSM_CONTEXT_PTR cc_context;
    CSSM_RETURN err;
    CSSM_DATA myBytes, digest;
    
    myBytes.Length = [self length];
    myBytes.Data = (void *)[self bytes];
    
    ctxt = CSSM_INVALID_HANDLE;
    digest.Data = NULL;
    cc_context = NULL;
    
    err = CSSM_CSP_CreateDigestContext(csp, algo, &ctxt);
    if (err != CSSM_OK)
        goto err;
    err = CSSM_GetContext(ctxt, &cc_context);
    if (err != CSSM_OK)
        goto err;
    
    digest.Length = 0;
    digest.Data = NULL;

    CSSM_FreeContext(cc_context);
    cc_context = NULL;

    err = CSSM_DigestData(ctxt, &myBytes, 1, &digest);
    if (err != CSSM_OK)
        goto err;
    CSSM_DeleteContext(ctxt);
    
    if (digest.Data == NULL)
        return nil;
    else
        return [NSData dataWithBytesNoCopy:digest.Data length:digest.Length freeWhenDone:YES];
    
err:
    if(cc_context)
        CSSM_FreeContext(cc_context);
    if (ctxt != CSSM_INVALID_HANDLE)
        CSSM_DeleteContext(ctxt);
    if (digest.Data)
        free(digest.Data);
    [cssmException(err, NULL) raise];
    return nil;
}

- (NSData *)signatureWithAlgorithm:(CSSM_ALGORITHMS)alg;
{
    CSSM_CSP_HANDLE csp;
    
    csp = [appleCSP() handle];
    NSData *result = [self signatureWithAlgorithm:alg csp:csp];
    return result;
}

@end

const CSSM_ALGORITHMS algs[] = {
    CSSM_ALGID_MD2, CSSM_ALGID_MD5, CSSM_ALGID_SHA1, CSSM_ALGID_SHA256, CSSM_ALGID_SHA384, CSSM_ALGID_SHA512, CSSM_ALGID_NONE
};

int main()
{
    int i;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSData *foo = [@"abc" dataUsingEncoding:NSASCIIStringEncoding];
    
    for(i = 0; algs[i] != CSSM_ALGID_NONE; i++) {
        NSAutoreleasePool *p2 = [[NSAutoreleasePool alloc] init];
        NSData *bar = [foo signatureWithAlgorithm:algs[i]];
        NSLog(@"%@ --%d--> %@", [foo unadornedLowercaseHexString], algs[i], [bar unadornedLowercaseHexString]);
        [p2 release];
    }
    
    [pool release];
    
    return 0;
}
