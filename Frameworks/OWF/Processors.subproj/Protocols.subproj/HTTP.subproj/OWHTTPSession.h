// Copyright 1999-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <Foundation/NSRange.h>
#import <OmniFoundation/OFBundleRegistryTarget.h>

@class NSArray, NSCharacterSet, NSLock, NSMutableArray;
@class ONSocketStream;
@class OWAddress, OWAuthorizationServer, OWHeaderDictionary, OWURL;
@class OWNetLocation;
@class OWPipeline, OWProcessor;
@class OWHTTPProcessor;
@class OWHTTPSessionQueue;
@class OWDataStream;
@class OWSitePreference;

@interface OWHTTPSession : OFObject <OFBundleRegistryTarget>
{
    // per session
    OWHTTPSessionQueue *queue;            // The queue of requests (processors) which are waiting to be assigned to a session
    OWNetLocation *proxyLocation;
    NSMutableArray *processorQueue;       // The processors whose requests we are currently handling (can be >1 for pipelined HTTP/1.1 requests)
    NSLock *processorQueueLock;
    ONSocketStream *socketStream;
    
    struct {
        unsigned int connectingViaProxyServer:1;
        unsigned int pipeliningRequests:1;
       // unsigned int foundCredentials:1;
       // unsigned int foundProxyCredentials:1;
        unsigned int serverIsLocal:1;
    } flags;
    unsigned int failedRequests;
    unsigned int requestsSentThisConnection;

    // holdover from an interrupted fetch
    OWDataStream *interruptedDataStream;
    NSRange desiredRange, receivedRange;

    NSArray *proxyCredentials;

    // per fetch
    OWAddress *fetchAddress;
    OWURL *fetchURL;
    OWHeaderDictionary *headerDictionary;
    struct {
        unsigned int distrustContentType: 1;
        unsigned int fakeAcceptHeader: 1;
        unsigned int fakeAcceptEncodingHeader: 1;
        unsigned int forceTrueIdentityInUAHeader: 1;
        unsigned int suppressAcceptEncodingHeader: 1;
    } kludge;
        

    struct {
        unsigned int incompleteResult:1;
    } fetchFlags;
}

+ (void)setDebug:(BOOL)shouldDebug;
+ (void)readDefaults;
+ (Class)socketClass;
    // Must return a subclass of ONInternetSocket
+ (int)defaultPort;
+ (NSArray *)browserIdentifierNames;
+ (NSDictionary *)browserIdentificationDictionaryForAddress:(OWAddress *)anAddress;
+ (NSString *)userAgentHeaderFormatStringForAddress:(OWAddress *)anAddress;
+ (NSString *)userAgentInfoForAddress:(OWAddress *)anAddress forceRevealIdentity:(BOOL)forceReveal;
+ (NSString *)primaryUserAgentInfo;
+ (NSString *)preferredDateFormat;
+ (NSArray *)acceptLanguages;
+ (NSString *)acceptLanguageValue;
+ (NSString *)acceptEncodingValue;

+ (NSCharacterSet *)nonTokenCharacterSet;  // set of characters not allowed in "token"s, RFC2068

- initWithAddress:(OWAddress *)anAddress inQueue:(OWHTTPSessionQueue *)aQueue;
- (void)runSession;
- (BOOL)prepareConnectionForProcessor:(OWProcessor *)aProcessor;
- (void)abortProcessingForProcessor:(OWProcessor *)aProcessor;

- (void)setStatusString:(NSString *)newStatus;
- (void)setStatusFormat:(NSString *)aFormat, ...;

@end

#define MAX_REQUESTS_TO_PIPELINE 3

typedef enum {
    HTTP_STATUS_CONTINUE = 100,
    HTTP_STATUS_SWITCHING_PROTOCOLS = 101,

    HTTP_STATUS_OK = 200,
    HTTP_STATUS_CREATED = 201,
    HTTP_STATUS_ACCEPTED = 202,
    HTTP_STATUS_NON_AUTHORITATIVE_INFORMATION = 203,
    HTTP_STATUS_NO_CONTENT = 204,
    HTTP_STATUS_RESET_CONTENT = 205,
    HTTP_STATUS_PARTIAL_CONTENT = 206,

    HTTP_STATUS_MULTIPLE_CHOICES = 300,
    HTTP_STATUS_MOVED_PERMANENTLY = 301,
    HTTP_STATUS_MOVED_TEMPORARILY = 302,
    HTTP_STATUS_SEE_OTHER = 303,
    HTTP_STATUS_NOT_MODIFIED = 304,
    HTTP_STATUS_USE_PROXY = 305,
    HTTP_STATUS_SWITCH_PROXY = 306,
    HTTP_STATUS_TEMPORARY_REDIRECT = 307,
    HTTP_STATUS_PERMANENT_REDIRECT = 308,

    HTTP_STATUS_BAD_REQUEST = 400,
    HTTP_STATUS_UNAUTHORIZED = 401,
    HTTP_STATUS_PAYMENT_REQUIRED = 402,
    HTTP_STATUS_FORBIDDEN = 403,
    HTTP_STATUS_NOT_FOUND = 404,
    HTTP_STATUS_METHOD_NOT_ALLOWED = 405,
    HTTP_STATUS_NONE_ACCEPTABLE = 406,
    HTTP_STATUS_PROXY_AUTHENTICATION_REQUIRED = 407,
    HTTP_STATUS_REQUEST_TIMEOUT = 408,
    HTTP_STATUS_CONFLICT = 409,
    HTTP_STATUS_GONE = 410,
    HTTP_STATUS_LENGTH_REQUIRED = 411,
    HTTP_STATUS_UNLESS_TRUE = 412,

    HTTP_STATUS_INTERNAL_SERVER_ERROR = 500,
    HTTP_STATUS_NOT_IMPLEMENTED = 501,
    HTTP_STATUS_BAD_GATEWAY = 502,
    HTTP_STATUS_SERVICE_UNAVAILABLE = 503,
    HTTP_STATUS_GATEWAY_TIMEOUT = 504,
} HTTPStatus;

@interface OWHTTPSession (SubclassesOnly)
- (void)connect;
- (void)disconnectAndRequeueProcessors;
- (BOOL)fetchForProcessor:(OWHTTPProcessor *)aProcessor;
- (NSString *)requestStringForProcessor:(OWHTTPProcessor *)aProcessor;
- (NSString *)authorizationStringForAddress:(OWAddress *)anAddress processor:(OWHTTPProcessor *)aProcessor;
- (NSString *)userAgentHeaderStringForAddress:(OWAddress *)anAddress;
- (BOOL)sendRequest;
- (BOOL)sendRequests;
@end

extern NSString *OWBrowserIdentity;
extern NSString *OWCustomBrowserIdentity;
extern NSString *OWCustomIdentityKey;

