// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSString;
@class OWAddress;

@interface OWDocumentTitle : OFObject

// Accessing titles
+ (NSString *)titleForAddress:(OWAddress *)address;
+ (void)cacheRealTitle:(NSString *)aTitle forAddress:(OWAddress *)anAddress;
+ (void)cacheGuessTitle:(NSString *)aTitle forAddress:(OWAddress *)anAddress;
+ (void)invalidateGuessTitleForAddress:(OWAddress *)anAddress;

// Notifications of changes to titles
+ (void)addObserver:(id)anObserver selector:(SEL)aSelector address:(OWAddress *)anAddress;
+ (void)removeObserver:(id)anObserver address:(OWAddress *)anAddress;
+ (void)removeObserver:(id)anObserver;
+ (void)postNotificationForAddress:(OWAddress *)anAddress;

@end
