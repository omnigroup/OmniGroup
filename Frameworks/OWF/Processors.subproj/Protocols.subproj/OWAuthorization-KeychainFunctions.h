// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Security/SecKeychain.h>
#import <Security/SecKeychainSearch.h>
#import <OWF/FrameworkDefines.h>

@class NSData, NSDictionary, NSMutableDictionary, NSString;

/* Get the raw bytes representing an item attribute. Returns nil if the item does not have that attribute. Raises an exception if an error occurs. */
OWF_PRIVATE_EXTERN NSData *OWKCGetItemAttribute(SecKeychainItemRef item, SecItemAttr attrTag);

/* Fetch several of the attributes of an item and convert them into reasonable Foundation types. Dictionary keys are the same as the attribute type constants defined in Apple's header, with the "kSec" and "ItemAttr" stripped off and the initial capital reduced to lower case. */
OWF_PRIVATE_EXTERN NSMutableDictionary *OWKCExtractItemAttributes(SecKeychainItemRef itemRef);

/* A cover for SecKeychainSearchCreateFromAttributes() which gets the item attributes from a dictionary. Dictionary keys & values are the same as would be returned by OWKCGetItemAttribute(). */
OWF_PRIVATE_EXTERN OSStatus OWKCBeginKeychainSearch(CFTypeRef chains, NSDictionary *attributes, SecKeychainSearchRef *grepstate);

/* Extracts the secret data from the keychain item (typically, this is the password) and returns it */
OWF_PRIVATE_EXTERN OSStatus OWKCExtractKeyData(SecKeychainItemRef item, NSData **password);

/* Updates a keychain item with the specified information */
OWF_PRIVATE_EXTERN OSStatus OWKCUpdateInternetPassword(NSString *hostname, NSString *realm, NSString *username, int portNumber, OSType protocol, OSType authType, NSData *passwordData);
