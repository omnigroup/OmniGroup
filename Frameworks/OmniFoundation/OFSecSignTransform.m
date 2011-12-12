// Copyright 2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
#import "OFSecSignTransform.h"
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFErrors.h>

RCS_ID("$Id$");

// #define DEBUG_OFSecSignTransform // Enables some log messages

@implementation OFSecSignTransform

- initWithKey:(SecKeyRef)aKey;
{
    if (!(self = [super init]))
        return nil;
    
    key = (SecKeyRef)CFRetain(aKey);
    
    return self;
}

- (void)dealloc
{
    [writebuffer release];
    if (key)
        CFRelease(key);
    if (digestType)
        CFRelease(digestType);

    [super dealloc];
}

- (void)setDigestType:(CFStringRef)newDigestType;
{
    OB_ASSIGN_CFRELEASE(digestType, newDigestType? CFStringCreateCopy(kCFAllocatorDefault, newDigestType) : NULL);
}
@synthesize digestType, digestLength;

- (BOOL)verifyInit:(NSError **)outError;
{
    if (writebuffer)
        OBRejectInvalidCall(self, _cmd, @"Invoked more than once");
    
    writebuffer = [[NSMutableData alloc] init];
    verifying = YES;
    return YES;
}

- (BOOL)generateInit:(NSError **)outError;
{
    if (writebuffer)
        OBRejectInvalidCall(self, _cmd, @"Invoked more than once");
    
    writebuffer = [[NSMutableData alloc] init];
    verifying = NO;
    return YES;
}

- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;
{
    [writebuffer appendBytes:buffer length:length];
    return YES;
}

static CFTypeRef setAttrsAndExecute(SecTransformRef transform, NSData *inputData, CFStringRef digestType, int digestLength, CFErrorRef *cfError)
{
    CFDataRef immutable = CFDataCreateCopy(kCFAllocatorDefault, (CFDataRef)inputData);
    Boolean success = SecTransformSetAttribute(transform, kSecTransformInputAttributeName, immutable, cfError);
    CFRelease(immutable);
    if (!success)
        return NULL;
    
#ifdef DEBUG_OFSecSignTransform
    // Setting kSecTransformDebugAttributeName logs a bunch of progress information.
    SecTransformSetAttribute(transform, kSecTransformDebugAttributeName, kCFBooleanTrue, NULL);
#endif
    
    if (digestType != NULL) {
        if (!SecTransformSetAttribute(transform, kSecDigestTypeAttribute, digestType, cfError))
            return NULL;
        
        if (digestLength > 0) {
            CFNumberRef dLen = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &digestLength);
            Boolean set = SecTransformSetAttribute(transform, kSecDigestLengthAttribute, dLen, cfError);
            CFRelease(dLen);
            if (!set)
                return NULL;
        }
    }
    
    if (!SecTransformSetAttribute(transform, kSecInputIsAttributeName, kSecInputIsPlainText, cfError))
        return NULL;
    
    CFErrorRef localError = NULL;
    CFTypeRef result = SecTransformExecute(transform, &localError);
    // NB: The example code (such as it is) seems to test the *error argument to determine success, instead of checking the result. Not sure whether this means the example code is wrong or SecTransform uses a different convention from the rest of the system. The documentation is not informative.
    if (localError) {
        if (cfError)
            *cfError = localError;
        else
            CFRelease(localError);
        result = NULL;
    }
    
#ifdef DEBUG_OFSecSignTransform
    NSString *desc = [(id)result description];
    if ([desc length] > 200) {
        desc = [[desc substringToIndex:150] stringByAppendingFormat:@"... (length=%lu)", (unsigned long)[desc length]];
    }
    NSLog(@"%@ -> [%@] %@ (%@=%@)", transform, localError? (id)localError : (id)@"OK", desc, kSecTransformOutputAttributeName, SecTransformGetAttribute(transform, kSecTransformOutputAttributeName));
#endif
    
    return result;
}

- (BOOL)verifyFinal:(NSData *)digest error:(NSError **)outError;
{
    if (!writebuffer || !verifying)
        OBRejectInvalidCall(self, _cmd, @"Called out of sequence");
    
    CFErrorRef cfError = NULL;
    SecTransformRef vrfy;
    CFTypeRef result;
    
    vrfy = SecVerifyTransformCreate(key, (CFDataRef)digest, &cfError);
    if (!vrfy)
        goto errorOut;
    
#ifdef DEBUG_OFSecSignTransform
    NSLog(@"Created %@ from %@", vrfy, OFSecItemDescription(key));
#endif
    
    result = setAttrsAndExecute(vrfy, writebuffer, digestType, digestLength, &cfError);
    if (!result) {
        CFRelease(vrfy);
        goto errorOut;
    }
    
    BOOL verifyOK;
    
    // There's no documentation on what a SecVerifyTransform returns. Experimentally, it seems to return a CFBoolean.
    if (CFGetTypeID(result) != CFBooleanGetTypeID()) {
        if (outError)
            *outError = [NSError errorWithDomain:OFErrorDomain code:OFXMLSignatureValidationError userInfo:[NSDictionary dictionaryWithObject:@"SecTransformExecute(SecVerifyTransform) returned non-boolean object" forKey:NSLocalizedDescriptionKey]];
        verifyOK = NO;
    } else if (!CFBooleanGetValue(result)) {
        if (outError)
            *outError = [NSError errorWithDomain:OFErrorDomain code:OFXMLSignatureValidationFailure userInfo:[NSDictionary dictionaryWithObject:@"SecTransformExecute(SecVerifyTransform) returned false" forKey:NSLocalizedDescriptionKey]];
        verifyOK = NO;
    } else {
        verifyOK = YES;
    }
    
    CFRelease(vrfy);
    
    return verifyOK;
    
    if (0) {
    errorOut:
        if (outError)
            *outError = [NSMakeCollectable(cfError) autorelease];
        else
            CFRelease(cfError);
        return NO;
    }
}

- (NSData *)generateFinal:(NSError **)outError;
{
    if (!writebuffer || verifying)
        OBRejectInvalidCall(self, _cmd, @"Called out of sequence");
    
    CFErrorRef cfError = NULL;
    CFTypeRef result;
    SecTransformRef gen = SecSignTransformCreate(key, &cfError);
    if (!gen)
        goto errorOut;
    
#ifdef DEBUG_OFSecSignTransform
    NSLog(@"Created %@ from %@", gen, OFSecItemDescription(key));
#endif
    
    result = setAttrsAndExecute(gen, writebuffer, digestType, digestLength, &cfError);
    if (!result) {
        CFRelease(gen);
        goto errorOut;
    }
    
    // Result is presumably kept alive by the SecTransform we got it from at this point; retain+autorelease for our caller.
    NSData *nsResult = [[(id)result retain] autorelease];
    
    CFRelease(gen);
    
    return nsResult;
    
    if (0) {
    errorOut:
        if (outError)
            *outError = [NSMakeCollectable(cfError) autorelease];
        else
            CFRelease(cfError);
        return nil;
    }
}

@end

#endif /* OSX 10.7 or later */
