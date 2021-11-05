// Copyright 2016-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OASecCertificateProxy.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#if defined(MAC_OS_VERSION_11_0) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_11_0
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

RCS_ID("$Id$")
OB_REQUIRE_ARC

@implementation OASecCertificateProxy
{
    SecCertificateRef certificate;
    NSData *derData;
    NSString *localizedDescription;
    enum { b_NO, b_YES, b_MAYBE } identityAvailable;
}

- (instancetype)initWithCertificate:(SecCertificateRef)cert;
{
    self = [super init];
    
    if (!cert)
        OBRejectInvalidCall(self, _cmd, @"certificate is NULL");
    
    certificate = (typeof(cert))CFRetain(cert);
    derData = (__bridge_transfer NSData *)SecCertificateCopyData(cert);
    identityAvailable = b_MAYBE;
    
    return self;
}

- (instancetype)initWithCertificate:(SecCertificateRef)cert hasPrivateKey:(BOOL)pka;
{
    self = [super init];
    
    if (!cert)
        OBRejectInvalidCall(self, _cmd, @"certificate is NULL");
    
    certificate = (typeof(cert))CFRetain(cert);
    derData = (__bridge_transfer NSData *)SecCertificateCopyData(cert);
    identityAvailable = pka? b_YES : b_NO;
    
    return self;
}

- (void)dealloc
{
    CFRelease(certificate);
}

@synthesize certificate = certificate;

- (NSComparisonResult)compare:(id)other;
{
    // Sort nil to the end of the list.
    if (!other || ![other isKindOfClass:[OASecCertificateProxy class]])
        return NSOrderedAscending;
    
    OASecCertificateProxy *obj = other;
    
    // Sort user's certificates before other peoples' certificates.
    BOOL otherHasPK = obj.hasPrivateKey;
    if (self.hasPrivateKey) { if (!otherHasPK) return NSOrderedAscending; }
    else                    { if ( otherHasPK) return NSOrderedDescending; }

    // Sort by the visible text.
    NSComparisonResult cmp = [self.localizedDescription localizedStandardCompare:obj.localizedDescription];
    
    // Finally, if we have the same visible text, compare the DER representation to provide a fixed ordering. We don't care what the ordering is here, as long as it's stable and different certificates don't compare equal.
    if (cmp == NSOrderedSame) {
        size_t len1 = derData.length;
        size_t len2 = obj->derData.length;
        int byteCmp = memcmp([derData bytes], [obj->derData bytes], MIN(len1, len2));
        // Due to the nature of DER encoding, one valid encoding can't be a prefix of the other.
        OBASSERT_IF(byteCmp == 0, len1 == len2);
        cmp = ( byteCmp < 0 )? NSOrderedAscending : ( (byteCmp == 0)? NSOrderedSame : NSOrderedDescending );
    }
    
    return cmp;
}

#pragma mark Pasteboard I/O

static dispatch_once_t utlookup_once;
static NSString *utTypePKIXCert, *utTypePEMFile, *utTypeCERFile;
static void utlookup(void *dummy) {
    if (@available(macOS 11, *)) { // eventually when we are macOS 11 and up, we shoudl just static the UTTypes instead of their identifiers
        utTypePKIXCert = [[UTType typeWithTag:@"application/pkix-cert" tagClass:UTTagClassMIMEType conformingToType:UTTypeData] identifier]; // Registered with IANA [RFC2585]
        utTypePEMFile = [[UTType typeWithTag:@"pem" tagClass:UTTagClassFilenameExtension conformingToType:UTTypeText] identifier]; // Typical file extension
        utTypeCERFile = [[UTType typeWithTag:@"cer" tagClass:UTTagClassFilenameExtension conformingToType:UTTypeItem] identifier]; // This is what we can get from Keychain Access, sometimes
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        utTypePKIXCert = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, CFSTR("application/pkix-cert"), kUTTypeData); // Registered with IANA [RFC2585]
        utTypePEMFile = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, CFSTR("pem"), kUTTypeText); // Typical file extension
        utTypeCERFile = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, CFSTR("cer"), kUTTypeItem); // This is what we can get from Keychain Access, sometimes
#pragma clang diagnostic pop
    }
}

+ (NSArray<NSString *> *)readableTypesForPasteboard:(NSPasteboard *)pasteboard;
{
    dispatch_once_f(&utlookup_once, NULL, utlookup);

    NSString *x509certIdentifier;
    
    if (@available(macOS 11, *)) {
        x509certIdentifier = UTTypeX509Certificate.identifier;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        x509certIdentifier = (__bridge NSString *)kUTTypeX509Certificate;
#pragma clang diagnostic pop
    }
        
    return [NSArray arrayWithObjects:x509certIdentifier, utTypePKIXCert, utTypePEMFile, utTypeCERFile, nil];
}

- (NSArray<NSString *> *)writableTypesForPasteboard:(NSPasteboard *)pasteboard;
{
    return [[[self class] readableTypesForPasteboard:pasteboard] arrayByAddingObject:(__bridge NSString *)kPasteboardTypeFileURLPromise];
}

+ (NSPasteboardReadingOptions)readingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard;
{
    dispatch_once_f(&utlookup_once, NULL, utlookup);
    BOOL conformsToPEM;
    
    if (@available(macOS 11, *)) {
        conformsToPEM = [[UTType typeWithIdentifier:type] conformsToType:[UTType typeWithIdentifier:utTypePEMFile]];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        conformsToPEM = UTTypeConformsTo((__bridge CFStringRef)type, (__bridge CFStringRef)utTypePEMFile);
#pragma clang diagnostic pop
    }
    
    if (conformsToPEM) {
        return NSPasteboardReadingAsString;
    } else {
        return NSPasteboardReadingAsData;
    }
}

- (nullable id)initWithPasteboardPropertyList:(id)propertyList ofType:(NSString *)type;
{
    self = [super init];
    
    NSData *der;
    
    dispatch_once_f(&utlookup_once, NULL, utlookup);

    BOOL conformsToPEM;
    if (@available(macOS 11, *)) {
        conformsToPEM = [[UTType typeWithIdentifier:type] conformsToType:[UTType typeWithIdentifier:utTypePEMFile]];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        conformsToPEM = UTTypeConformsTo((__bridge CFStringRef)type, (__bridge CFStringRef)utTypePEMFile);
#pragma clang diagnostic pop
    }
    
    if (conformsToPEM) {
        return nil; // TODO
    } else if ([propertyList isKindOfClass:[NSData class]]) {
        der = propertyList;
    } else {
        return nil;
    }
    
    SecCertificateRef cert = SecCertificateCreateWithData(kCFAllocatorDefault, (__bridge CFDataRef)der);
    if (!cert) {
        return nil;
    }
    
    certificate = cert;
    derData = der;
    identityAvailable = b_MAYBE;
    
    return self;
}

- (nullable id)pasteboardPropertyListForType:(NSString *)type;
{
    BOOL conformsToText;
    if (@available(macOS 11, *)) {
        conformsToText = [[UTType typeWithIdentifier:type] conformsToType:UTTypeText];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        conformsToText = UTTypeConformsTo((__bridge CFStringRef)type, kUTTypeText);
#pragma clang diagnostic pop
    }

    if (conformsToText) {
        return [NSString stringWithFormat:@"-----BEGIN CERTIFICATE-----\n%@\n-----END CERTIFICATE-----\n", [derData base64EncodedStringWithOptions:NSDataBase64Encoding76CharacterLineLength|NSDataBase64EncodingEndLineWithLineFeed]];
    } else {
        return derData;
    }
}

#pragma mark Pasteboard file promise provider

- (NSString *)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider fileNameForType:(NSString *)fileType;
{
    NSString *fileExtension;
    if (@available(macOS 11, *)) {
        fileExtension = [UTType typeWithIdentifier:fileType].preferredFilenameExtension;
        if (fileExtension == nil) {
            fileExtension = @".der";
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CFStringRef ext = UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)fileType, kUTTagClassFilenameExtension);
        fileExtension = ext? ((__bridge_transfer NSString *)ext) : @".der";
#pragma clang diagnostic pop
    }
    
    return [self.localizedDescription stringByAppendingPathExtension:fileExtension];
}

- (void)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider writePromiseToURL:(NSURL *)url completionHandler:(void (^)(NSError * __nullable errorOrNil))completionHandler;
{
    NSError * __autoreleasing errorBuffer = nil;
    if ([derData writeToURL:url options:0 error:&errorBuffer]) {
        completionHandler(nil);
    } else {
        OBASSERT(errorBuffer != nil);
        completionHandler(errorBuffer);
    }
}

#pragma mark UI usefulness

static dispatch_once_t lookupImages_once;
static NSImage *smallPersonalIcon, *smallStandardIcon;
static void lookupImages(void *dummy) {
    NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.apple.securityinterface"];
    smallPersonalIcon = [bundle imageForResource:@"CertSmallPersonal"];
    smallStandardIcon = [bundle imageForResource:@"CertSmallStd"];
}

- (NSImage *)icon;
{
    dispatch_once_f(&lookupImages_once, NULL, lookupImages);
    
    if (self.hasPrivateKey) {
        return smallPersonalIcon;
    } else {
        return smallStandardIcon;
    }
}

- (NSString *)localizedDescription;
{
    if (!localizedDescription) {
        CFStringRef summary = SecCertificateCopySubjectSummary(certificate);
        localizedDescription = (__bridge_transfer NSString *)summary;
    }
    
    return localizedDescription;
}

- (BOOL)hasPrivateKey;
{
    if (identityAvailable == b_MAYBE) {
        SecIdentityRef foundIdentity = NULL;
        if (SecIdentityCreateWithCertificate(kCFAllocatorDefault, certificate, &foundIdentity) == noErr) {
            if (foundIdentity != NULL) {
                identityAvailable = b_YES;
                CFRelease(foundIdentity);
            } else {
                identityAvailable = b_NO;
            }
        } else {
            identityAvailable = b_NO;
        }
    }
    
    return ( identityAvailable == b_YES )? YES : NO;
}

@end



