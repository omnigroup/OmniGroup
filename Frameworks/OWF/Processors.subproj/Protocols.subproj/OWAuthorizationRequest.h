// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

// An OWAuthorizationRequest encapsulates one request from a protocol processor for authentication information. It checks the credential cache, etc., but its main purpose is to manage the user dialogue (the document- or app-modal prompt, and dealing with the event loop / background-thread synchronization).

@class NSArray, NSData, NSDictionary, NSConditionLock, NSSet, NSString;
@class OWNetLocation, OWHeaderDictionary;
@class OWAuthorizationCredential;
@protocol OWProcessorContext;

@interface OWAuthorizationRequest : NSObject
{
    enum OWAuthorizationType {
        OWAuth_HTTP,
        OWAuth_HTTP_Proxy,
        OWAuth_FTP,
        OWAuth_NNTP
    } type;
    OWNetLocation *server;
    id <OWProcessorContext,NSObject> pipeline;
    OWHeaderDictionary *challenge;
    
    NSArray *theseDidntWork;
    
    // Parsed version of above for creating new credentials
    NSString *parsedHostname;
    unsigned int parsedPortnumber;
    unsigned int defaultPortnumber;
    NSArray *parsedChallenges;
    
    // Synchronization
    
    NSConditionLock *requestCondition;  // has condition=YES if request has completed
    NSArray *results;                   // cached results (nil means we prompted the user and failed)
    NSString *errorString;              // String error message if we've had an error
}

extern NSString * const OWAuthorizationCacheChangedNotificationName;

// Users of the framework can install a subclass of this class which knows how to do user interaction
+ (Class)authorizationRequestClass;
+ (void)setAuthorizationRequestClass:(Class)aClass;

// remove cached credentials
+ (void)flushCache:sender;

// Returns an NSData which depends on the contents of the credential cache. 
+ (NSData *)entropy;

// Parse authentication headers into an array of dictionaries
+ (NSArray *)findParametersOfType:(enum OWAuthorizationType)type headers:(OWHeaderDictionary *)challenge;

// The default initializer. Once created, an OWAuthReq. immediately starts trying to satisfy itself (possibly in another thread)
- initForType:(enum OWAuthorizationType)authType netLocation:(OWNetLocation *)aHost defaultPort:(unsigned)defaultPort context:(id <OWProcessorContext,NSObject>)aPipe challenge:(OWHeaderDictionary *)aChallenge promptForMoreThan:(NSArray *)theseDidntWork;

// accessors
- (enum OWAuthorizationType)type;
- (NSString *)hostname;
- (unsigned int)port;

- (NSArray *)credentials;
- (NSString *)errorString;   // if -credentials retuirns nil

// ??? move to private?
- (BOOL)checkForSatisfaction;
- (void)failedToCreateCredentials:(NSString *)reason;

// returns YES if the credentials cache was updated
+ (BOOL)cacheCredentialIfAbsent:(OWAuthorizationCredential *)newCredential;
- (BOOL)cacheUsername:(NSString *)aName password:(id)aPassword forChallenge:(NSDictionary *)useParameters;
- (BOOL)cacheUsername:(NSString *)aName password:(id)aPassword forChallenge:(NSDictionary *)useParameters saveInKeychain:(BOOL)saveInKeychain;

@end

@interface OWAuthorizationRequest (KeychainPrivate)
- (NSSet *)keychainTags;
- (BOOL)getPasswordFromKeychain:(NSDictionary *)useParameters;
@end

extern NSString * const OWAuthorizationRequestKeychainExceptionName;
extern NSString * const OWAuthorizationRequestKeychainExceptionKeychainStatusKey;
