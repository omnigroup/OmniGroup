// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <OmniFoundation/OFFeatures.h>

#if !OF_ENABLE_NET_STATE
#error Should not be imported on this platform
#endif

/*
 Publishes the state of a local resource that peers in the same group might be interested in.
 Instances of this class can be used from any thread, but access to a single instance must be protected from access by multiple concurrent threads.
 
 The member identifier specifies an individual in a group. If a member changes its state, OFNetStateNotifier instances that have the same member identifier will ignore that change (since they are part of the change).
 */

@interface OFNetStateRegistration : NSObject

+ (BOOL)netServiceName:(NSString *)serviceName matchesAnyGroup:(NSSet *)groupIdentifiers;

- initWithGroupIdentifier:(NSString *)groupIdentifier memberIdentifier:(NSString *)memberIdentifier name:(NSString *)name state:(NSData *)state NS_EXTENSION_UNAVAILABLE_IOS("This depends on UIApplication, which isn't available in application extensions");

- (void)invalidate;

@property(nonatomic,readonly) NSString *name; // Debugging; this will be included in the service name, but might be truncated
@property(nonatomic,readonly) NSString *registrationIdentifier; // Unique to this specific instance
@property(nonatomic,readonly) NSString *groupIdentifier;
@property(nonatomic,readonly) NSString *memberIdentifier;

// Some opaque data describing the current local state. If this is too long, its SHA-1 will be used instead.
@property(nonatomic,copy) NSData *localState;

@end

extern NSString * const OFNetStateServiceType;
extern NSString * const OFNetStateServiceDomain;

extern NSString * const OFNetStateRegistrationGroupIdentifierKey;
extern NSString * const OFNetStateRegistrationMemberIdentifierKey;
extern NSString * const OFNetStateRegistrationStateKey;
extern NSString * const OFNetStateRegistrationVersionKey;

extern NSData *OFNetStateTXTRecordDataFromDictionary(NSDictionary *dictionary, BOOL addTypePrefixes);
extern NSDictionary *OFNetStateTXTRecordDictionaryFromData(NSData *txtRecord, BOOL expectTypePrefixes, __autoreleasing NSString **outErrorString);
