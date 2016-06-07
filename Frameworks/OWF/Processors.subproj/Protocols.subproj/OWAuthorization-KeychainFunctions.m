// Copyright 2001-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWAuthorization-KeychainFunctions.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <Security/SecKeychainItem.h>

RCS_ID("$Id$");

#if 0

static OSStatus extractSomeItemAttributes(SecKeychainItemRef itemRef, FourCharCode *itemClassp, NSMutableDictionary *into, const FourCharCode *attributesToExtract, unsigned int numberOfAttributes);

static struct { FourCharCode tag; NSString *str; } tagNames[] = {
{ kSecAccountItemAttr, @"account" },
{ kSecAddressItemAttr, @"address" },
{ kSecAuthenticationTypeItemAttr, @"authenticationType" },
{ kSecCommentItemAttr, @"comment" },
{ kSecCreationDateItemAttr, @"creationDate" },
{ kSecCreatorItemAttr, @"creator" },
{ kSecCustomIconItemAttr, @"customIcon" },
{ kSecDescriptionItemAttr, @"description" },
{ kSecGenericItemAttr, @"generic" },
{ kSecInvisibleItemAttr, @"invisible" },
{ kSecLabelItemAttr, @"label" },
{ kSecModDateItemAttr, @"modDate" },
{ kSecNegativeItemAttr, @"negative" },
{ kSecPathItemAttr, @"path" },
{ kSecPortItemAttr, @"port" },
{ kSecProtocolItemAttr, @"protocol" },
{ kSecScriptCodeItemAttr, @"scriptCode" },
{ kSecSecurityDomainItemAttr, @"securityDomain" },
{ kSecServerItemAttr, @"server" },
{ kSecServiceItemAttr, @"service" },
{ kSecSignatureItemAttr, @"signature" },
{ kSecTypeItemAttr, @"type" },
{ kSecVolumeItemAttr, @"volume" },
#if 0
/* We don't do any PKC stuff yet, but when we do, we'll want these attribute names */
{ kSecCertEncodingItemAttr, @"certEncoding" },
{ kSecCertTypeItemAttr, @"certType" },
{ kSecIssuerItemAttr, @"issuer" },
{ kSecPublicKeyHashItemAttr, @"publicKeyHash" },
{ kSecSerialNumberItemAttr, @"serialNumber" },
{ kSecSubjectItemAttr, @"subject" },
{ kSecSubjectKeyIdentifierItemAttr, @"subjectKeyIdentifier" },
#endif
{ 0, nil }
};

static NSString *stringForAttributeTag(FourCharCode aTag)
{
    int tableIndex;

    for(tableIndex = 0; tagNames[tableIndex].str != nil; tableIndex ++)
        if (tagNames[tableIndex].tag == aTag)
            return tagNames[tableIndex].str;

    return [NSString stringWithFormat:@"0x%08X", (unsigned int)aTag];
}

#if 0
/* This'll be big enough for practically everything. On the off chance it's too small, we try again. */
/* NOTE: KCGetAttribute() will do invisible silent *format conversions* on some attributes if you say you have an 8-byte buffer! What was Apple smoking? */
#define INITIAL_TRY_LENGTH 128  /* change to 9 or so for debug */

NSData *OWKCGetItemAttribute(SecKeychainItemRef item, SecItemAttr attrTag)
{
    SecKeychainAttribute attr;
    OSStatus keychainStatus;
    UInt32 actualLength;
    void *freeMe = NULL;
    
    attr.tag = attrTag;
    actualLength = INITIAL_TRY_LENGTH;
    attr.length = actualLength;  /* KCGetAttribute() doesn't appear to write this field, at least in Cheetah4K29, but it may read it */
    attr.data = alloca(actualLength);
        
    keychainStatus = KCGetAttribute(item, &attr, &actualLength);
    if (keychainStatus == errKCBufferTooSmall) {
        /* the attribute length will have been placed into actualLength */
        freeMe = malloc(actualLength);
        attr.length = actualLength;
        attr.data = freeMe;
        keychainStatus = KCGetAttribute(item, &attr, &actualLength);
    }
    if (keychainStatus == noErr) {
        NSData *retval = [NSData dataWithBytes:attr.data length:actualLength];
	if (freeMe != NULL)
            free(freeMe);
        // NSLog(@"attr '%c%c%c%c' value %@", ((char *)&attrTag)[0], ((char *)&attrTag)[1], ((char *)&attrTag)[2], ((char *)&attrTag)[3], retval);
        return retval;
    }
    
    if (freeMe != NULL)
        free(freeMe);

    if (keychainStatus == errKCNoSuchAttr) {
        /* An expected error. Return nil for nonexistent attributes. */
        return nil;
    }
    
    /* An unexpected error, probably indicating a real problem. Raise an exception. */
    [NSException raise:@"Keychain error" format:@"Error number %d occurred while trying to fetch an item attribute, and Apple's too stingy to include a strerror() equivalent.", keychainStatus];
    
    return nil;  // appease the dread compiler warning gods
}

#endif

static inline NSString *parseKeychainString(NSData *strbytes) {
    // Trim trailing nulls here, since some strings have 'em and some don't. This could break multibyte encodings, so when we fix those (see above) we'll have to change this as well.
    if ([strbytes length] && (((char *)[strbytes bytes])[[strbytes length]-1] == 0))
        strbytes = [strbytes subdataWithRange:NSMakeRange(0, [strbytes length]-1)];
    return [[[NSString alloc] initWithData:strbytes encoding:NSUTF8StringEncoding] autorelease];
}

#if 0
static NSDate *parseKeychainDate(NSData *date)
{
    NSString *text;
    NSDate *retval;
    
    /* The documentation states that keychain creation and mod-time dates are UInt32, but in fact they appear to be ASCII strings in a packed calendar format. */
    if ([date length] <= 8) {
        /* Are these Unix-style seconds-since-1970, or Mac-style seconds-since-1900 ? Nobody knows. */
        [NSException raise:@"Keychain error" format:@"Unexpected timestamp format in keychain item."];
    }
    
    text = parseKeychainString(date);
    retval = [NSCalendarDate dateWithString:text calendarFormat:@"%Y%m%d%H%M%SZ"];
    if (!retval) {
        NSLog(@"Couldn't convert date: %@", text);
        return [NSDate distantPast];
    }
    return retval;
}
#endif

static NSNumber *parseKeychainInteger(NSData *value) {
    // Endianness? Portability? Bah! We don't need no portability! Everything's a Macintosh now!
    UInt32 int4 = 0;
    UInt16 int2 = 0;
    UInt8 int1 = 0;
    
    switch([value length]) {
        case 4:
            [value getBytes:&int4];
            break;
        case 2:
            [value getBytes:&int2];
            int4 = int2;
            break;
        case 1:
            [value getBytes:&int1];
            int4 = int1;
            break;
        default:
            [NSException raise:@"Keychain error" format:@"Unexpected integer format in keychain item."];
    }
    
    return [NSNumber numberWithUnsignedInt:int4];
}

static id parseKeychainAttribute(SecKeychainAttribute attr)
{
    NSData *asData;

    if (attr.data == NULL)
        return nil;

    asData = [NSData dataWithBytes:attr.data length:attr.length];

    switch(attr.tag) {
        case kSecDescriptionItemAttr:
        case kSecCommentItemAttr:
        case kSecLabelItemAttr:
        case kSecSecurityDomainItemAttr:
        case kSecPathItemAttr:
            if (attr.length == 0)
                return nil;
        case kSecServerItemAttr:
        case kSecServiceItemAttr:
        case kSecAccountItemAttr:
            return parseKeychainString(asData);

        case kSecPortItemAttr:
        case kSecInvisibleItemAttr:
        case kSecNegativeItemAttr:
        case kSecCustomIconItemAttr:
            return parseKeychainInteger(asData);

        default:
            return asData;
    }
}

#define UNIVERSAL_ATTRIBUTES_COUNT 8
static const FourCharCode universalItemAttributes[UNIVERSAL_ATTRIBUTES_COUNT] = {
    kSecCreationDateItemAttr, kSecModDateItemAttr, kSecDescriptionItemAttr, kSecCommentItemAttr,
    kSecCreatorItemAttr, kSecTypeItemAttr, kSecScriptCodeItemAttr, kSecLabelItemAttr
};

#define GENERIC_PSW_ATTRIBUTES_COUNT 2
static const FourCharCode genpItemAttributes[GENERIC_PSW_ATTRIBUTES_COUNT] = {
    kSecServiceItemAttr, kSecAccountItemAttr
};

#define INET_PSW_ATTRIBUTES_COUNT 7
static const FourCharCode inetPasswordItemAttributes[INET_PSW_ATTRIBUTES_COUNT] = {
    kSecSecurityDomainItemAttr, kSecServerItemAttr, kSecAuthenticationTypeItemAttr,
    kSecProtocolItemAttr, kSecPortItemAttr, kSecPathItemAttr, kSecAccountItemAttr
};

NSMutableDictionary *OWKCExtractItemAttributes(SecKeychainItemRef itemRef)
{
    NSMutableDictionary *dict = [[[NSMutableDictionary alloc] initWithCapacity:13] autorelease];
    OSStatus osErr;
    FourCharCode itemClass;
    
    /* Get the item's class. While we're at it, extract any attributes common to all items. */
    itemClass = 0;
    osErr = extractSomeItemAttributes(itemRef, &itemClass, dict, universalItemAttributes, UNIVERSAL_ATTRIBUTES_COUNT);
    if (osErr != noErr)
        [NSException raise:@"Keychain error" format:@"Unable to read keychain item attributes (apple says: %d)", osErr];
    
    /* Get any class-specific attributes */
    switch (itemClass) {
        case kSecGenericPasswordItemClass:
            osErr = extractSomeItemAttributes(itemRef, NULL, dict, genpItemAttributes, GENERIC_PSW_ATTRIBUTES_COUNT);
            break;
        case kSecInternetPasswordItemClass:
            osErr = extractSomeItemAttributes(itemRef, NULL, dict, inetPasswordItemAttributes, INET_PSW_ATTRIBUTES_COUNT);
            break;
        default:
            osErr = noErr;
            break;
    }

    if (osErr != noErr)
        [NSException raise:@"Keychain error" format:@"Unable to read keychain '%@' attributes (apple says: %d)", [NSString stringWithFourCharCode:itemClass], osErr];

    return dict;
}

static OSStatus extractSomeItemAttributes(SecKeychainItemRef itemRef, FourCharCode *itemClassp, NSMutableDictionary *into, const FourCharCode *attributesToExtract, unsigned int numberOfAttributes)
{
    OSStatus osErr;
    FourCharCode itemClass;
    SecKeychainAttributeList resultList;
    SecKeychainAttribute resultAttributes[numberOfAttributes];
    unsigned attributeIndex;

    resultList.count = numberOfAttributes;
    resultList.attr = resultAttributes;
    for(attributeIndex = 0; attributeIndex < numberOfAttributes; attributeIndex ++) {
        resultAttributes[attributeIndex].tag = attributesToExtract[attributeIndex];
        resultAttributes[attributeIndex].length = 0;
        resultAttributes[attributeIndex].data = NULL;
    }

    osErr = SecKeychainItemCopyContent(itemRef, &itemClass, &resultList, NULL, NULL);
    if (osErr != noErr)
        return osErr;

    if ([into objectForKey:kSecClass] == nil)
        [into setObject:[NSData dataWithBytes:&itemClass length:sizeof(itemClass)] forKey:kSecClass];
    if (itemClassp)
        *itemClassp = itemClass;

    for(attributeIndex = 0; attributeIndex < resultList.count; attributeIndex ++) {
        id value = parseKeychainAttribute(resultList.attr[attributeIndex]);
        if (value)
            [into setObject:value forKey:stringForAttributeTag(resultList.attr[attributeIndex].tag)];
    }

    osErr = SecKeychainItemFreeContent(&resultList, NULL);

    return osErr;
}

#if 0
static NSData *formatKeychain4CC(id value)
{
    // catch NSStrings containing decimal numbers (bleah)
    if ([value isKindOfClass:[NSString class]] && (([value length] == 0) || ([value length] != 4 && [value unsignedIntValue] != 0))) {
        value = [NSNumber numberWithUnsignedInt:[value unsignedIntValue]];
    }

    if ([value isKindOfClass:[NSData class]])
        return value;
    if ([value isKindOfClass:[NSNumber class]]) {
        UInt32 aCode = [value unsignedIntValue];
        return [NSData dataWithBytes:&aCode length:sizeof(aCode)];
    }
    
    return [value dataUsingEncoding:[NSString defaultCStringEncoding]];
}

static NSData *formatKeychainString(id value)
{
    return [value dataUsingEncoding:[NSString defaultCStringEncoding]];
}

static NSData *formatKeychainInteger(id value)
{
    UInt32 int4;
    
    int4 = [value intValue];
    return [NSData dataWithBytes:&int4 length:sizeof(int4)];
}
#endif

#if 0
static SecKeychainAttribute *KeychainAttributesFromDictionary(NSDictionary *params, UInt32 *returnAttributeCount, FourCharCode *returnItemClass)
{
    SecKeychainAttribute *attributes;
    unsigned attributeCount, attributeIndex;
    NSEnumerator *paramNameEnumerator;
    NSString *paramName;

    OBPRECONDITION(returnAttributeCount != NULL);
    attributeCount = [params count];
    attributes = malloc(sizeof(*attributes) * attributeCount);
    attributeIndex = 0;

    paramNameEnumerator = [params keyEnumerator];
    while ( (paramName = [paramNameEnumerator nextObject]) != nil) {
        id paramValue = [params objectForKey:paramName];
        NSData *data;

        if ([paramName isEqualToString:@"class"]) {
            if (returnItemClass != NULL) {
                data = formatKeychain4CC(paramValue);
                *returnItemClass = *(FourCharCode *)[data bytes];
            }
            continue;
        } else if ([paramName isEqualToString:@"description"]) {
            attributes[attributeIndex].tag = kSecDescriptionItemAttr;
            data = formatKeychainString(paramValue);
        } else if ([paramName isEqualToString:@"account"]) {
            attributes[attributeIndex].tag = kSecAccountItemAttr;
            data = formatKeychainString(paramValue);
        } else if ([paramName isEqualToString:@"service"]) {
            attributes[attributeIndex].tag = kSecServiceItemAttr;
            data = formatKeychainString(paramValue);
        } else if ([paramName isEqualToString:@"securityDomain"]) {
            attributes[attributeIndex].tag = kSecSecurityDomainItemAttr;
            data = formatKeychainString(paramValue);
        } else if ([paramName isEqualToString:@"server"]) {
            attributes[attributeIndex].tag = kSecServerItemAttr;
            data = formatKeychainString(paramValue);
        } else if ([paramName isEqualToString:@"authType"] ||
                   [paramName isEqualToString:@"authenticationType"]) {
            attributes[attributeIndex].tag = kSecAuthenticationTypeItemAttr;
            data = formatKeychain4CC(paramValue);
        } else if ([paramName isEqualToString:@"port"]) {
            attributes[attributeIndex].tag = kSecPortItemAttr;
            data = formatKeychainInteger(paramValue);
        } else if ([paramName isEqualToString:@"path"]) {
            attributes[attributeIndex].tag = kSecPathItemAttr;
            data = formatKeychainString(paramValue);
        } else if ([paramName isEqualToString:@"protocol"]) {
            attributes[attributeIndex].tag = kSecProtocolItemAttr;
            data = formatKeychain4CC(paramValue);
        } else {
            // this shouldn't happen.
            continue;
        }

        attributes[attributeIndex].length = [data length];
        attributes[attributeIndex].data = (char *)[data bytes];
        attributeIndex++;
    }
    *returnAttributeCount = attributeIndex;
    return attributes;
}
#endif

OSStatus OWKCBeginKeychainSearch(CFTypeRef chains, NSDictionary *params, SecKeychainSearchRef *grepstate)
{
    OBFinishPorting; // Uses keychain API that was deprecated in 10.7
#if 0
    SecKeychainAttributeList attributeList;

    if (!params || ![params count]) {
	return SecKeychainSearchCreateFromAttributes(chains, kSecInternetPasswordItemClass, NULL, grepstate);
    } else {
        OSStatus keychainStatus;
        SecItemClass itemClass;

        itemClass = kSecInternetPasswordItemClass;
        attributeList.attr = KeychainAttributesFromDictionary(params, &attributeList.count, &itemClass);
                
        keychainStatus = SecKeychainSearchCreateFromAttributes(chains, itemClass, &attributeList, grepstate);
        free(attributeList.attr);
        return keychainStatus;
    }
#endif
}

#endif

OSStatus OWKCUpdateInternetPassword(NSString *hostname, NSString *realm, NSString *username, int portNumber, SecProtocolType protocol, SecAuthenticationType authType, NSData *passwordData)
{
    SecKeychainRef keychain = NULL; // default keychain
    const char *serverName = [hostname UTF8String];
    UInt32 serverNameLength = (UInt32)(serverName != NULL ? strlen(serverName) : 0);
    const char *securityDomain = [realm UTF8String];
    UInt32 securityDomainLength = (UInt32)(securityDomain != NULL ? strlen(securityDomain) : 0);
    const char *accountName = [username UTF8String];
    UInt32 accountNameLength = (UInt32)(accountName != NULL ? strlen(accountName) : 0);

    SecKeychainItemRef itemRef;
    OSStatus err = SecKeychainFindInternetPassword(keychain, serverNameLength, serverName, securityDomainLength, securityDomain, accountNameLength, accountName, 0 /* pathLength */, NULL /* path */, portNumber, protocol, authType, NULL /* &passwordLength */, NULL /* &passwordData */, &itemRef);
    if (err == errSecSuccess) {
        err = SecKeychainItemModifyAttributesAndData(itemRef, NULL /* attributes */, (UInt32)[passwordData length], [passwordData bytes]);
        CFRelease(itemRef);
    } else if (err == errSecItemNotFound) {
        // Add a new entry.
        err = SecKeychainAddInternetPassword(keychain, serverNameLength, serverName, securityDomainLength, securityDomain, accountNameLength, accountName, 0 /* pathLength */, NULL /* path */, portNumber, protocol, authType, (UInt32)[passwordData length], [passwordData bytes], NULL /* &itemRef */);
    }

    return err;
}

OSStatus OWKCExtractKeyData(SecKeychainItemRef item, NSData **password)
{
    UInt32 dataLength = 0;
    void *dataBuf = NULL;

    OSStatus keychainStatus = SecKeychainItemCopyAttributesAndData(item, NULL, NULL, NULL, &dataLength, &dataBuf);

    if (keychainStatus == noErr) {
        *password = [NSData dataWithBytes:dataBuf length:dataLength];
        SecKeychainItemFreeAttributesAndData(NULL, dataBuf);
    } else
        *password = nil;

    return keychainStatus;
}
