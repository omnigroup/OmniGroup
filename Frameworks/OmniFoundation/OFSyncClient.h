// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSDate.h> // NSTimeInterval

NS_ASSUME_NONNULL_BEGIN

@class NSString, NSURL;
@class OFPreference, OFSyncClientParameters, OFVersionNumber;

extern NSMutableDictionary *OFSyncBaseClientState(NSString *domain, NSString *clientIdentifier, NSDate *registrationDate);

extern NSString *OFSyncClientIdentifier(NSDictionary *clientState);
extern NSDate *OFSyncClientLastSyncDate(NSDictionary *clientState);
extern NSString * _Nullable OFSyncClientApplicationIdentifier(NSDictionary *clientState);
extern OFVersionNumber *OFSyncClientVersion(NSDictionary *clientState);
extern NSString *OFSyncClientHardwareModel(NSDictionary *clientState);

extern NSDate *OFSyncClientDateWithTimeIntervalSinceNow(NSTimeInterval sinceNow);

extern NSDictionary *OFSyncClientRequiredState(OFSyncClientParameters *parameters, NSString *clientIdentifier, NSDate *registrationDate);


// Allows multiple clients per app (particularly for tests)
@interface OFSyncClientParameters : NSObject

- (id)initWithDefaultClientIdentifierPreferenceKey:(NSString *)defaultClientIdentifierPreferenceKey hostIdentifierDomain:(NSString *)hostIdentifierDomain currentFrameworkVersion:(OFVersionNumber *)currentFrameworkVersion;

@property(nonatomic,readonly) NSString *defaultClientIdentifierPreferenceKey;
@property(nonatomic,readonly) NSString *hostIdentifierDomain;
@property(nonatomic,copy) OFVersionNumber *currentFrameworkVersion; // Writable for tests -- don't change once the instance is being used.

@property(nonatomic,readonly) OFPreference *defaultClientIdentifierPreference;
@property(nonatomic,readonly) NSString *defaultClientIdentifier;

- (BOOL)isClientStateFromCurrentHost:(NSDictionary *)clientState;

@end

@interface OFSyncClient : NSObject

// Adds plist-safe entries to a dictionary with helpful information about this client. Can be extended by subclasses (though we don't have good namespacing of the keys in the dictionary for backwards compatibility...). Only pass nil for a newly registered client.
+ (NSMutableDictionary *)makeClientStateWithPreviousState:(nullable NSDictionary *)oldClientState parameters:(OFSyncClientParameters *)parameters onlyIncludeRequiredKeys:(BOOL)onlyRequiredKeys;

+ (NSString *)computerName;

- (nullable id)initWithURL:(NSURL *)clientURL previousClient:(nullable OFSyncClient *)previousClient parameters:(OFSyncClientParameters *)parameters error:(NSError **)outError;
- (nullable id)initWithURL:(NSURL *)clientURL propertyList:(NSDictionary *)propertyList error:(NSError **)outError;

@property(nonatomic,readonly) NSURL *clientURL;
@property(nonatomic,readonly) NSDictionary *propertyList;

@property(nonatomic,readonly) NSString *identifier;
@property(nonatomic,readonly) NSDate *registrationDate;
@property(nonatomic,readonly) NSDate *lastSyncDate;
@property(nonatomic,readonly) NSString *name;
@property(nonatomic,readonly) NSString *hardwareModel;

- (BOOL)lastSyncDatePastLimitDate:(NSDate *)limitDate;
- (NSComparisonResult)compareByLastSyncDate:(OFSyncClient *)otherClient;

// The version number of the sync framework this client is using. Other clients should not upgrade the remote sync repository to a newer version than this. Older clients should not touch the sync repository if their version is older than its current version.
@property(nonatomic,readonly) OFVersionNumber *currentFrameworkVersion;

@property(nonatomic,readonly,nullable) OFVersionNumber *applicationMarketingVersion;

@end

NS_ASSUME_NONNULL_END
