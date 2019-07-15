// Copyright 2004-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <OmniBase/assertions.h>
#import <OmniFoundation/OFXMLIdentifierRegistryObject.h>

@class NSMutableDictionary;

@interface OFXMLIdentifierRegistry : NSObject

- (id)initWithRegistry:(OFXMLIdentifierRegistry *)registry;

- (NSString *)registerIdentifier:(NSString *)identifier forObject:(id <OFXMLIdentifierRegistryObject>)object;
- (id <OFXMLIdentifierRegistryObject>)objectForIdentifier:(NSString *)identifier;
- (NSString *)identifierForObject:(id <OFXMLIdentifierRegistryObject>)object;

- (void)applyBlock:(void (^)(NSString *identifier, id <OFXMLIdentifierRegistryObject> object))block;

- (void)clearRegistrations;
- (NSUInteger)registrationCount;

- (NSMutableDictionary *)copyIdentifierToObjectMapping;

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)checkInvariants;
- (BOOL)isSubsetOfRegistry:(OFXMLIdentifierRegistry *)otherRegistry;
#endif

@end

extern NSString *OFXMLIDFromString(NSString *str);
