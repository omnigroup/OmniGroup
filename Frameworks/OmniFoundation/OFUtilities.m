// Copyright 1997-2005, 2007-2008, 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>

#import <CoreFoundation/CoreFoundation.h>
#import <CoreServices/CoreServices.h> // for Debugging.h
#import <Foundation/NSData.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <pthread.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#import <OmniBase/OmniBase.h>


RCS_ID("$Id$")

#define OF_GET_INPUT_CHUNK_LENGTH 80

void OFLog(NSString *messageFormat, ...)
{
    va_list argList;
    NSString *message;

    va_start(argList, messageFormat);
    message = [[[NSString alloc] initWithFormat:messageFormat arguments:argList] autorelease];
    va_end(argList);

    fputs([message UTF8String], stdout);
}

NSString *OFGetInput(NSStringEncoding encoding, NSString *promptFormat, ...)
{
    va_list argList;
    NSString *prompt;
    NSString *input;
    char buf[OF_GET_INPUT_CHUNK_LENGTH];

    va_start(argList, promptFormat);
    prompt = [[[NSString alloc] initWithFormat:promptFormat arguments:argList] autorelease];
    va_end(argList);

    printf("%s", [prompt UTF8String]);
    input = [NSString string];
    while (!ferror(stdin)) {
        memset(buf, 0, sizeof(buf));
        if (fgets(buf, sizeof(buf), stdin) == NULL) {
            // EOF
            break;
        }
        
        input = [input stringByAppendingString:[NSString stringWithCString:buf encoding:encoding]];
        if ([input hasSuffix:@"\n"])
            break;
    }

    if ([input length])
        return [input substringToIndex:[input length] - 1];

    return nil;
}

#if 0 // Should probably use KVC
void OFSetIvar(NSObject *object, NSString *ivarName, NSObject *ivarValue)
{
    Ivar ivar;
    id *ivarSlot;

    // TODO:At some point, this function should take a void * and should look at the type of the ivar and deal with scalar values correctly.

    ivar = class_getInstanceVariable(*(Class *) object, [ivarName cString]);
    OBASSERT(ivar);

    ivarSlot = (id *)((char *)object + ivar->ivar_offset);

    if (*ivarSlot != ivarValue) {
	[*ivarSlot release];
	*ivarSlot = [ivarValue retain];
    }
}

NSObject *OFGetIvar(NSObject *object, NSString *ivarName)
{
    Ivar ivar;
    id *ivarSlot;

    ivar = class_getInstanceVariable(*(Class *) object, [ivarName cString]);
    OBASSERT(ivar);

    ivarSlot = (id *)((char *)object + ivar->ivar_offset);

    return *ivarSlot;
}
#endif

BOOL OFInstanceIsKindOfClass(id instance, Class aClass)
{
    Class sourceClass = object_getClass(instance);

    while (sourceClass) {
        if (sourceClass == aClass)
            return YES;
        sourceClass = class_getSuperclass(sourceClass);
    }
    return NO;
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
NSString *OFDescriptionForObject(id object, NSDictionary *locale, unsigned indentLevel)
{
    if ([object isKindOfClass:[NSString class]])
        return object;
    else if ([object respondsToSelector:@selector(descriptionWithLocale:indent:)])
        return [(id)object descriptionWithLocale:locale indent:indentLevel + 1];
    else  if ([object respondsToSelector:@selector(descriptionWithLocale:)])
        return [(id)object descriptionWithLocale:locale];
    else
        return [NSString stringWithFormat: @"%@%@",
            [NSString spacesOfLength:(indentLevel + 1) * 4],
            [object description]];
}
#endif

/*"
Ensures that the given selName maps to a registered selector.  If it doesn't, a copy of the string is made and it is registered with the runtime.  The registered selector is returned, in any case.
"*/
SEL OFRegisterSelectorIfAbsent(const char *selName)
{
    SEL sel;

    if (!(sel = sel_getUid(selName))) {
        // The documentation isn't clear on whether the input string is copied or not.
        // On NS4.0 and later, sel_registerName copies the selector name.  But
        // we won't assume that is the case -- we'll make a temporary copy
        // and get the assertion rather than crashing the runtime (in case they
        // change this in the future).
        char *newSel = strdup(selName);
        sel = sel_registerName(newSel);

        // Make sure the copy happened
        OBASSERT((void *)sel_getUid(selName) != (void *)newSel);
        OBASSERT((void *)sel != (void *)newSel);

        free(newSel);
    }

    return sel;
}

// Lots of SystemConfiguration is deprecated on the iPhone; need to write another path if we want this.
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <SystemConfiguration/SystemConfiguration.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

// uint32_t since we are explicitly looking for IPv4 and so we don't require in_addr_t in the header
uint32_t OFLocalIPv4Address(void)
{
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, (CFStringRef)[[NSProcessInfo processInfo] processName], NULL, NULL);
    
    CFStringRef interfacesKey = SCDynamicStoreKeyCreateNetworkInterface(NULL, kSCDynamicStoreDomainState);
    NSDictionary *interfacesDictionary = (NSDictionary *)SCDynamicStoreCopyValue(store, interfacesKey);
    CFRelease(interfacesKey);
    
    NSArray *interfaces = [interfacesDictionary objectForKey:(NSString *)kSCDynamicStorePropNetInterfaces];
    for (NSString *interfaceName in interfaces) {
        {
            CFStringRef linkKey = SCDynamicStoreKeyCreateNetworkInterfaceEntity(NULL, kSCDynamicStoreDomainState, (CFStringRef)interfaceName, kSCEntNetLink);
            CFDictionaryRef linkDictionary = SCDynamicStoreCopyValue(store, linkKey);
            CFRelease(linkKey);
            
            if (!linkDictionary)
                continue;
            
            BOOL isActive = [(NSDictionary *)linkDictionary boolForKey:(NSString *)kSCPropNetLinkActive];
            CFRelease(linkDictionary);
            
            if (!isActive)
                continue;
        }

        CFArrayRef ipAddresses = NULL;
        {
            CFStringRef ipv4Key = SCDynamicStoreKeyCreateNetworkInterfaceEntity(NULL, kSCDynamicStoreDomainState, (CFStringRef)interfaceName, kSCEntNetIPv4);
            CFDictionaryRef ipv4Dictionary = SCDynamicStoreCopyValue(store, ipv4Key);
            if (ipv4Dictionary != NULL) {
                ipAddresses = CFDictionaryGetValue(ipv4Dictionary, kSCPropNetIPv4Addresses);
                if (ipAddresses)
                    CFRetain(ipAddresses);
                CFRelease(ipv4Dictionary);
            }
            if (ipv4Key)
                CFRelease(ipv4Key);
        }

        if (ipAddresses != NULL && CFArrayGetCount(ipAddresses) != 0) {
            NSString *ipAddressString = [(NSArray *)ipAddresses objectAtIndex:0];
            in_addr_t address = inet_addr([ipAddressString UTF8String]);
            if (address != (unsigned int)-1) {
                CFRelease(ipAddresses);
                CFRelease(interfacesDictionary);
                CFRelease(store);
                
                OBASSERT(address <= UINT32_MAX);
                return (uint32_t)address;
            }
        }
        if (ipAddresses)
            CFRelease(ipAddresses);
    }
    if (interfacesDictionary)
        CFRelease(interfacesDictionary);
    CFRelease(store);
    return (in_addr_t)INADDR_LOOPBACK; // Localhost (127.0.0.1)
}
#endif


NSString *OFISOLanguageCodeForEnglishName(NSString *languageName)
{
    return [OMNI_BUNDLE localizedStringForKey:languageName value:@"" table:@"EnglishToISO"];
}

NSString *OFLocalizedNameForISOLanguageCode(NSString *languageCode)
{
    return [OMNI_BUNDLE localizedStringForKey:languageCode value:@"" table:@"Language"];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
NSString *OFOSStatusDescription(OSStatus err)
{
    /* Deprecated without an adequate replacement in 10.8. RADAR 12514739 */
    
    const char *longErrorDescription = GetMacOSStatusCommentString(err);
    if (longErrorDescription && strlen(longErrorDescription))
        return [NSString stringWithFormat:@"%s (%"PRI_OSStatus")", longErrorDescription, err];
    
    const char *shErrDesc = GetMacOSStatusErrorString(err);
    if (shErrDesc && strlen(shErrDesc))
        return [NSString stringWithFormat:@"%s (%"PRI_OSStatus")", shErrDesc, err];
    
    return [NSString stringWithFormat:@"%"PRI_OSStatus"", err];
}
#pragma clang diagnostic pop

// Adapted from OmniNetworking. May be replaced by something cleaner in the future.

#import <sys/ioctl.h>
#import <sys/socket.h>
#import <net/if.h>
#import <net/if_dl.h>         // for 'struct sockaddr_dl'
#import <unistd.h>		// for close()

// We'll guess that this is wildly larger than the maximum number of interfaces on the machine.  I don't see that there is a way to get the number of interfaces so that you don't have to have a hard-coded value here.  Sucks.
#define MAX_INTERFACES 100

#define IFR_NEXT(ifr)	\
    ((struct ifreq *) ((char *) (ifr) + sizeof(*(ifr)) + \
                   MAX(0, (int) (ifr)->ifr_addr.sa_len - (int) sizeof((ifr)->ifr_addr))))

static NSDictionary *InterfaceAddresses = nil;

static NSDictionary *OFLinkLayerInterfaceAddresses(void)
{
    if (InterfaceAddresses != nil) // only need to do this once
        return InterfaceAddresses;

    int interfaceSocket;
    if ((interfaceSocket = socket(AF_INET, SOCK_DGRAM, 0)) < 0) 
        [NSException raise:NSGenericException format:@"Unable to create temporary socket, errno = %d", OMNI_ERRNO()];

    struct ifreq requestBuffer[MAX_INTERFACES];
    struct ifconf ifc;
    ifc.ifc_len = sizeof(requestBuffer);
    ifc.ifc_buf = (caddr_t)requestBuffer;
    if (ioctl(interfaceSocket, SIOCGIFCONF, &ifc) != 0) {
        close(interfaceSocket);
        [NSException raise:NSGenericException format:@"Unable to get list of network interfaces, errno = %d", OMNI_ERRNO()];
    }

    NSMutableDictionary *interfaceAddresses = [NSMutableDictionary dictionary];
    
    struct ifreq *linkInterface = (struct ifreq *) ifc.ifc_buf;
    while ((char *) linkInterface < &ifc.ifc_buf[ifc.ifc_len]) {
        // The ioctl returns both the entries having the address (AF_INET) and the link layer entries (AF_LINK).  The AF_LINK entry has the link layer address which contains the interface type.  This is the only way I can see to get this information.  We cannot assume that we will get both an AF_LINK and AF_INET entry since the interface may not be configured.  For example, if you have a 10Mb port on the motherboard and a 100Mb card, you may not configure the motherboard port.

        // For each AF_LINK entry...
        if (linkInterface->ifr_addr.sa_family == AF_LINK) {
            unsigned int nameLength;
            for (nameLength = 0; nameLength < IFNAMSIZ; nameLength++)
                if (linkInterface->ifr_name[nameLength] == '\0')
                    break;
            
            NSString *ifname = [[[NSString alloc] initWithBytes:linkInterface->ifr_name length:nameLength encoding:NSASCIIStringEncoding] autorelease];
            // get the link layer address (for ethernet, this is the MAC address)
            struct sockaddr_dl *linkSocketAddress = (struct sockaddr_dl *)&linkInterface->ifr_addr;
            int linkLayerAddressLength = linkSocketAddress->sdl_alen;
            
            if (linkLayerAddressLength > 0) {
                const unsigned char *bytes = (unsigned char *)LLADDR(linkSocketAddress);
                NSMutableString *addressString = [NSMutableString string];
                
                int byteIndex;
                for (byteIndex = 0; byteIndex < linkLayerAddressLength; byteIndex++) {
                    if (byteIndex > 0)
                        [addressString appendString:@":"];
                    unsigned int byteValue = (unsigned int)bytes[byteIndex];
                    [addressString appendFormat:@"%02x", byteValue];
                }
                [interfaceAddresses setObject:addressString forKey:ifname];
            }
        }
        linkInterface = IFR_NEXT(linkInterface);
    }

    close(interfaceSocket);
    InterfaceAddresses = [interfaceAddresses copy];
    return InterfaceAddresses;
}

// There is no perfect unique identifier for a machine since Apple doesn't guarantee that the machine's serial number will be accessible or present.  It's unclear if the caveats to the machine serial number are really for old Macs or current ones.
static NSString *_OFCalculateUniqueMachineIdentifier(void)
{
    NSDictionary *interfaces = OFLinkLayerInterfaceAddresses();
        
#ifdef DEBUG_kc0
    NSLog(@"Interfaces = %@", [[interfaces allKeys] sortedArrayUsingSelector:@selector(compare:)]);
#endif
    // Prefer the 'en0' interface for backwards compatibility.
    NSString *identifier = [interfaces objectForKey:@"en0"];
    
    if (![NSString isEmptyString:identifier])
        return identifier;
    
    // If there is no such interface (it can get renamed, for one thing -- see RT ticket 191290>), look for another.  Sort the interface names so we don't suffer changes based on 
    NSArray *names = [[interfaces allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        identifier = [interfaces objectForKey:name];
        if (![NSString isEmptyString:identifier])
            return identifier;
    }
    
    // TODO: We could try using the machine's serial number via <http://developer.apple.com/technotes/tn/tn1103.html>, but even this can fail.  Often all we want is a globally unique string that at least lasts until the machine is rebooted.  It would be nice if the machine had a 'boot-uuid'... perhaps we could write a file in /tmp with a UUID that we'd check for before generating our own.  Race conditions would be an issue there (particularly at login with multple apps auto-launching).
    OBASSERT_NOT_REACHED("No active interfaces?");
    return @"no unique machine identifier found";
}

NSString *OFUniqueMachineIdentifier(void)
{
    static NSString *uniqueMachineIdentifier = nil;

    if (uniqueMachineIdentifier == nil)
        uniqueMachineIdentifier = [_OFCalculateUniqueMachineIdentifier() retain];
    return uniqueMachineIdentifier;
}

NSString *OFHostName(void)
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    return @"localhost";
#else

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    NSString *hostname = nil;
    SCDynamicStoreRef dynamicStore = SCDynamicStoreCreate(kCFAllocatorDefault, (CFStringRef)OMNI_BUNDLE_IDENTIFIER, NULL, NULL);
    CFStringRef hostnameKey = SCDynamicStoreKeyCreateHostNames(kCFAllocatorDefault);
    
    if (dynamicStore && hostnameKey) {
        CFPropertyListRef value = SCDynamicStoreCopyValue(dynamicStore, hostnameKey);
        if (value) {
            OBASSERT(CFGetTypeID(value) == CFDictionaryGetTypeID());
            if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
                NSDictionary *dictionary = (NSDictionary *)value;
                hostname = [[[dictionary objectForKey:@"HostName"] copy] autorelease];
                if (!hostname) {
                    hostname = [dictionary objectForKey:@"LocalHostName"];
                    if (hostname) {
                        OBASSERT(![hostname hasSuffix:@".local"]);
                        hostname = [NSString stringWithFormat:@"%@.local", hostname];
                    }
                }
            }       
        
            CFRelease(value);
        }
    }
    
    if (dynamicStore) CFRelease(dynamicStore);
    if (hostnameKey) CFRelease(hostnameKey);

    return hostname ? hostname : @"localhost";
#else
    NSString *hostname = nil;
    char hostnameBuffer[MAXHOSTNAMELEN + 1];
    if (gethostname(hostnameBuffer, MAXHOSTNAMELEN) == 0) {
        hostnameBuffer[MAXHOSTNAMELEN] = '\0'; // Ensure that the C string is NUL terminated
        hostname = [[NSString alloc] initWithCString:hostnameBuffer encoding:NSASCIIStringEncoding];
    } else {
        hostname = @"localhost";
    }

    return hostname;
#endif
#endif
}

NSString *OFLocalHostName(void)
{
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    CFStringRef localHostName = SCDynamicStoreCopyLocalHostName(NULL);
    return [(id)CFMakeCollectable(localHostName) autorelease];
#else
    return 
#endif    
}

static inline char _toHex(unsigned int i)
{
    if (i <= 9)
        return '0' + i;
    if (i >= 0xa && i <= 0xf)
        return 'a' + i;
    return '?';
}

static inline unsigned int _fillByte(unsigned char c, char *out)
{
    if (isascii(c)) {
        *out = c;
        return 1;
    } else {
        out[0] = '\\';
        out[1] = _toHex(c >> 4);
        out[2] = _toHex(c & 0xf);
        return 3;
    }
}

char *OFFormatFCC(uint32_t fcc, char fccString[13])
{
    char *s = fccString;

    s = s + _fillByte((fcc & 0xff000000) >> 24, s);
    s = s + _fillByte((fcc & 0x00ff0000) >> 16, s);
    s = s + _fillByte((fcc & 0x0000ff00) >>  8, s);
    s = s + _fillByte((fcc & 0x000000ff) >>  0, s);
    *s = '\0';

    return fccString;
}

// Sigh. UTGetOSTypeFromString() / UTCreateStringForOSType() are in ApplicationServices, which we don't want to link from Foundation. Sux.
// Taking this opportunity to make the API a little better.
static BOOL ofGet4CCFromNSData(NSData *d, uint32_t *v)
{
    union {
        uint32_t i;
        char c[4];
    } buf;
    
    if ([d length] == 4) {
        [d getBytes:buf.c];
        *v = CFSwapInt32BigToHost(buf.i);
        return YES;
    } else {
        return NO;
    }
}

BOOL OFGet4CCFromPlist(id pl, uint32_t *v)
{
    if (!pl)
        return NO;
    
    if ([pl isKindOfClass:[NSString class]]) {
        
        /* Special case thanks to UTCreateStringForOSType() */
        if ([pl length] == 0) {
            *v = 0;
            return YES;
        }
        
        NSData *d = [(NSString *)pl dataUsingEncoding:NSMacOSRomanStringEncoding allowLossyConversion:NO];
        if (d)
            return ofGet4CCFromNSData(d, v);
        else
            return NO;
    }
    
    if ([pl isKindOfClass:[NSData class]])
        return ofGet4CCFromNSData((NSData *)pl, v);
    
    if ([pl isKindOfClass:[NSNumber class]]) {
        *v = [pl unsignedIntValue];
        return YES;
    }
    
    return NO;
}

id OFCreatePlistFor4CC(uint32_t v)
{
    // Characters which are maybe less-than-safe to store in an NSString: either characters which are invalid in MacRoman, or which produce combining marks instead of plain characters (e.g., MacRoman 0x41 0xFB could undergo Unicode recombination and come out as 0x81).
    static const uint32_t ok_chars[8] = {
        0x00000000u, 0xAFFFFF3Bu, 0xFFFFFFFFu, 0x7FFFFFFFu,
        0xFFFFFFFFu, 0xFFFFE7FFu, 0xFFFFFFFFu, 0x113EFFFFu
    };
    union {
        uint32_t i;
        UInt8 c[4];
    } buf;
    
#define OK(ch) ( ok_chars[ch / 32] & (1 << (ch % 32)) )
    buf.i = CFSwapInt32HostToBig(v);
    
    if (!OK(buf.c[0]) || !OK(buf.c[1]) || !OK(buf.c[2]) || !OK(buf.c[3]))
        return [[NSData alloc] initWithBytes:buf.c length:4];
    else {
        CFStringRef s = CFStringCreateWithBytes(kCFAllocatorDefault, buf.c, 4, kCFStringEncodingMacRoman, FALSE);
        return NSMakeCollectable(s);
    }
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <ApplicationServices/ApplicationServices.h> // CGFloat
#endif

static const struct {
    const char *typespec;
    CFNumberType cfNumberType;
} cfNumberTypes[] = {
    // This works because @encode returns an encoding indicating the concrete implementation of a type, so that for example @encode(pid_t) and @encode(int) both return "i" (since pid_t is currently typedef'd to int32_t, and the compiler int is 32 bits).
    // Note that on versions later than 10.1, there's no precise way to represent an unsigned int in an NSNumber/CFNumber (despite the existence of +numberWithUnsignedInt:): RADAR #3513632. (In 10.5, +numberWithUnsignedInt: produces a kCFNumberSInt64Type, which at least is better than the old behavior of interpreting the arg as signed... In general, CFNumber is much less flexible than the NSNumber it replaced.)

    // Also note that the types here are somewhat redundant (SInt32 is the same as an int right now); using @encode ensures that the table is accurate, but there will be two or three entries for any given ObjC type.
        
#define T(t) { @encode(t), kCFNumber ## t ## Type }
    T(SInt8), T(SInt16), T(SInt32), T(SInt64), T(Float32), T(Float64),
#if defined(MAC_OS_X_VERSION_10_5) && (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5)
    T(NSInteger), T(CGFloat),
    // Yep, there's no kCFNumberNSUIntegerType. WTF, Apple?!?
#endif
#undef T
    
#define T(n, v) { @encode(n), kCFNumber ## v ## Type }
    T(char, Char),
    T(short, Short),
    T(int, Int),
    T(long, Long),
    T(float, Float),
    T(double, Double),
#undef T
    
    { NULL, 0 }
};

CFNumberType OFCFNumberTypeForObjCType(const char *objCType)
{
    int i;
    for(i = 0; cfNumberTypes[i].typespec != NULL; i ++) {
        if (!strcmp(objCType, cfNumberTypes[i].typespec))
            return cfNumberTypes[i].cfNumberType;
    }
    
    OBASSERT_NOT_REACHED("ObjC type with no corresponding CFNumber type");
    return 0;
}

const char *OFObjCTypeForCFNumberType(CFNumberType cfType)
{
    int i;
    for(i = 0; cfNumberTypes[i].typespec != NULL; i ++) {
        if (cfNumberTypes[i].cfNumberType == cfType)
            return cfNumberTypes[i].typespec;
    }
    
    // This should never happen, unless Apple adds more types to CoreFoundation and we don't add them to the array.
    OBASSERT_NOT_REACHED("CFNumber type with no corresponding ObjC type");
    return NULL;
}

