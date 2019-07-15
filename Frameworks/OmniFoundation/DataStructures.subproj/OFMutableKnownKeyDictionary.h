// Copyright 1998-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSDictionary.h>

@class OFKnownKeyDictionaryTemplate;

@interface OFMutableKnownKeyDictionary : NSMutableDictionary
/*.doc.
This subclass of NSMutableDictionary should be used when the set of possible keys is small and known ahead of time.  Due to the variable size of instances, this class cannot be easily subclassed.
*/

+ (OFMutableKnownKeyDictionary *) newWithTemplate: (OFKnownKeyDictionaryTemplate *)aTemplate;
/*.doc.
 Returns a new, retained, empty instance.
*/

- (OFMutableKnownKeyDictionary *) mutableKnownKeyCopyWithZone: (NSZone *) zone NS_RETURNS_RETAINED;
/*.doc.
Returns a new retained mutable copy of the receive.  This is named as it is so that -mutableCopyWithZone: will still return a vanilla NSMutableDictionary.
*/

- (NSArray *) copyKeys;

- (void)addLocallyAbsentValuesFromDictionary:(OFMutableKnownKeyDictionary *)fromDictionary;

- (void)enumerateKeysAndObjectPairsWithDictionary:(OFMutableKnownKeyDictionary *)pairDictionary usingBlock:(void (^)(id key, id object1, id object2, BOOL *))block;

@end

