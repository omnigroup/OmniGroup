// Copyright 2011-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSecSignTransform.h"

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFErrors.h>

RCS_ID("$Id$");

// #define DEBUG_OFSecSignTransform // Enables some log messages

@implementation OFSecSignTransform
{
    NSMutableData *writebuffer;
    SecKeyRef key;
    CFStringRef digestType;
    int digestLength;
    int generatorGroupOrderLog2;
    BOOL verifying;
}

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
- (void)setPackDigestsWithGroupOrder:(int)sizeInBits;
{
    OBASSERT(sizeInBits > 0);
    generatorGroupOrderLog2 = sizeInBits;
}

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

static CFTypeRef setAttrsAndExecute(SecTransformRef transform, NSData *inputData, CFStringRef digestType, int digestLength, CFErrorRef *cfError) CF_RETURNS_RETAINED;

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
    
    CFTypeRef result = SecTransformExecute(transform, cfError);
    // NB: The example code (such as it is) seems to test the *error argument to determine success, instead of checking the result. Not sure whether this means the example code is wrong or SecTransform uses a different convention from the rest of the system. The documentation is not informative.
    //
    // The example code must be wrong in the error case. The documentation does say, about the errorRef:
    //    "An optional pointer to a CFErrorRef. This value will be set if an error occurred during initialization or execution of the transform or group. If not NULL the caller will be responsible for releasing the returned CFErrorRef."
    // The return value, therefore, must indicate success or failure.
    // I'm dropping the localError that used to be here, and letting it just fall through the normal path.
    // This also quiets the warning that the static analyzer in Apple LLVM compiler 4.0 generates about this code.

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
    
    if (generatorGroupOrderLog2) {
        NSData *unpacked = OFDigestConvertDLSigToDER(digest, generatorGroupOrderLog2, outError);
        if (!unpacked)
            return NO;
        OBINVARIANT([OFDigestConvertDLSigToPacked(unpacked, generatorGroupOrderLog2, NULL) isEqual:digest]);
        digest = unpacked;
    }
    
    CFErrorRef cfError = NULL;
    SecTransformRef vrfy;
    CFTypeRef result;
    
    vrfy = SecVerifyTransformCreate(key, (__bridge CFDataRef)digest, &cfError);
    if (!vrfy) {
        if (outError)
            *outError = CFBridgingRelease(cfError);
        else
            CFRelease(cfError);
        return NO;
    }
    
#ifdef DEBUG_OFSecSignTransform
    NSLog(@"Created %@ from %@", vrfy, OFSecItemDescription(key));
#endif
    
    result = setAttrsAndExecute(vrfy, writebuffer, digestType, digestLength, &cfError);
    if (!result) {
        CFRelease(vrfy);
        if (outError)
            *outError = CFBridgingRelease(cfError);
        else
            CFRelease(cfError);
        return NO;
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
    CFRelease(result);
    
    return verifyOK;
}

- (NSData *)generateFinal:(NSError **)outError;
{
    if (!writebuffer || verifying)
        OBRejectInvalidCall(self, _cmd, @"Called out of sequence");
    
    CFErrorRef cfError = NULL;
    CFTypeRef result;
    SecTransformRef gen = SecSignTransformCreate(key, &cfError);
    if (!gen) {
        if (outError)
            *outError = CFBridgingRelease(cfError);
        else
            CFRelease(cfError);
        return nil;
    }
    
#ifdef DEBUG_OFSecSignTransform
    NSLog(@"Created %@ from %@", gen, OFSecItemDescription(key));
#endif
    
    result = setAttrsAndExecute(gen, writebuffer, digestType, digestLength, &cfError);
    if (!result) {
        CFRelease(gen);
        
        if (outError)
            *outError = CFBridgingRelease(cfError);
        else
            CFRelease(cfError);
        return nil;
    }
    
    OBASSERT(CFGetTypeID(result) == CFDataGetTypeID());
    
    // Result is presumably CFRetained by the SecTransform we got it from at this point; convert to NS retain+autorelease for our caller.
    NSData *nsResult = (OB_BRIDGE NSData *)result;
    CFRelease(gen);
    
    if (generatorGroupOrderLog2) {
        NSData *packed = OFDigestConvertDLSigToPacked(nsResult, generatorGroupOrderLog2, outError);
        if (packed != nil) {
            OBINVARIANT([OFDigestConvertDLSigToDER(packed, generatorGroupOrderLog2, NULL) isEqual:nsResult]);
        }
        [nsResult release];
        return packed; // May be nil, if OFDigestConvertDLSigToPacked() failed
    } else {
        return [nsResult autorelease];
    }
}

@end
