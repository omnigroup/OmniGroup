// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Security/SecKeychain.h>
#import <Security/SecKeychainSearch.h>

@class NSData, NSDictionary, NSMutableDictionary, NSString;

#if 0
/* Get the raw bytes representing an item attribute. Returns nil if the item does not have that attribute. Raises an exception if an error occurs. */
extern NSData *OWKCGetItemAttribute(SecKeychainItemRef item, SecItemAttr attrTag) OB_HIDDEN;

/* Fetch several of the attributes of an item and convert them into reasonable Foundation types. Dictionary keys are the same as the attribute type constants defined in Apple's header, with the "kSec" and "ItemAttr" stripped off and the initial capital reduced to lower case. */
extern NSMutableDictionary *OWKCExtractItemAttributes(SecKeychainItemRef itemRef) OB_HIDDEN;

/* A cover for SecKeychainSearchCreateFromAttributes() which gets the item attributes from a dictionary. Dictionary keys & values are the same as would be returned by OWKCGetItemAttribute(). */
extern OSStatus OWKCBeginKeychainSearch(CFTypeRef chains, NSDictionary *attributes, SecKeychainSearchRef *grepstate) OB_HIDDEN;

#endif

/* Updates a keychain item with the specified information */
extern OSStatus OWKCUpdateInternetPassword(NSString *hostname, NSString *realm, NSString *username, int portNumber, SecProtocolType protocol, SecAuthenticationType authType, NSData *passwordData) OB_HIDDEN;

/* Extracts the secret data from the keychain item (typically, this is the password) and returns it */
extern OSStatus OWKCExtractKeyData(SecKeychainItemRef item, NSData **password) OB_HIDDEN;
