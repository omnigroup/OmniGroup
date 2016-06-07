// Copyright 2016 Omni Development. Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/Foundation.h>

extern NSArray *retrieveFromKeychain(NSData *applicationTag, NSError **outError);

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
extern BOOL storeInKeychain(CFDataRef keymaterial, CFDataRef applicationLabel, NSString *userVisibleLabel, NSError **outError);
#else
extern BOOL storeInKeychain(CFDataRef keymaterial, CFDataRef keylabel, NSString *displayName, NSError **outError);
extern OSStatus removeItemFromKeychain(SecKeychainItemRef keyRef);
#endif

#if 0
extern OSStatus removeDerivations(CFStringRef attrKey, NSData *attrValue);
#endif

extern NSData *retrieveItemData(CFTypeRef item, CFTypeRef itemClass);

#if 0 && TARGET_OS_IPHONE
extern BOOL retrieveFromKeychain(NSDictionary *docInfo, uint8_t *localKey, size_t localKeyLength, CFStringRef allowUI, NSError **outError);
#endif
