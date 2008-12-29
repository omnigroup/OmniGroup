// Copyright 1998-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFMutableKnownKeyDictionary.h 68913 2005-10-03 19:36:19Z kc $

#import <Foundation/NSDictionary.h>

@class OFKnownKeyDictionaryTemplate;

typedef void (*OFMutableKnownKeyDictionaryApplier)(id key, id value, void *context);
typedef void (*OFMutableKnownKeyDictionaryPairApplier)(id key, id value1, id value2, void *context);

@interface OFMutableKnownKeyDictionary : NSMutableDictionary
/*.doc.
This subclass of NSMutableDictionary should be used when the set of possible keys is small and known ahead of time.  Due to the variable size of instances, this class cannot be easily subclassed.
*/
{
    OFKnownKeyDictionaryTemplate *_template;
    NSObject                     *_values[0];
}

+ (OFMutableKnownKeyDictionary *) newWithTemplate: (OFKnownKeyDictionaryTemplate *)aTemplate zone: (NSZone *) zone;
/*.doc.
Returns a new, retained, empty instance.
*/

+ (OFMutableKnownKeyDictionary *) newWithTemplate: (OFKnownKeyDictionaryTemplate *)aTemplate;
/*.doc.
Calls +newWithTemplate:zone: using the default zone.
*/

- (OFMutableKnownKeyDictionary *) mutableKnownKeyCopyWithZone: (NSZone *) zone;
/*.doc.
Returns a new retained mutable copy of the receive.  This is named as it is so that -mutableCopyWithZone: will still return a vanilla NSMutableDictionary.
*/

- (NSArray *) copyKeys;

- (void)addLocallyAbsentValuesFromDictionary:(OFMutableKnownKeyDictionary *)fromDictionary;

- (void)applyFunction:(OFMutableKnownKeyDictionaryApplier)function context:(void *)context;

- (void)applyPairFunction:(OFMutableKnownKeyDictionaryPairApplier)function pairDictionary:(OFMutableKnownKeyDictionary *)pairDictionary context:(void *)context;

@end

