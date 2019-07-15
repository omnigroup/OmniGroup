// Copyright 1999-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class OWAddress;
@class NSMutableArray;
@class NSMutableSet;
@class NSLock;
@class OWHTTPProcessor;
@class OWHTTPSession;
@class OFDatedMutableDictionary;

@interface OWHTTPSessionQueue : OFObject
{
    OWAddress *address;
    NSMutableArray *idleSessions;
    NSMutableArray *sessions;
    NSMutableArray *queuedProcessors;
    NSMutableSet *abortedProcessors;
    NSLock *lock;
    struct {
        unsigned int serverUnderstandsPipelinedRequests:1;
        unsigned int serverCannotHandlePipelinedRequestsReliably:1;
    } flags;
}

+ (OWHTTPSessionQueue *)httpSessionQueueForAddress:(OWAddress *)anAddress;
+ (NSString *)cacheKeyForSessionQueueForAddress:(OWAddress *)anAddress;
+ (Class)sessionClass;
+ (OFDatedMutableDictionary *)cache;
+ (NSUInteger)maximumSessionsPerServer;

- initWithAddress:(OWAddress *)anAddress;
- (BOOL)queueProcessor:(OWHTTPProcessor *)aProcessor;
- (void)runSession;
- (void)abortProcessingForProcessor:(OWHTTPProcessor *)aProcessor;

- (OWHTTPProcessor *)nextProcessor;
- (OWHTTPProcessor *)anyProcessor;
- (BOOL)sessionIsIdle:(OWHTTPSession *)session;
- (void)session:(OWHTTPSession *)session hasStatusString:(NSString *)statusString;

- (BOOL)queueEmptyAndAllSessionsIdle;
- (NSString *)queueKey;

- (void)setServerUnderstandsPipelinedRequests;
- (BOOL)serverUnderstandsPipelinedRequests;
- (void)setServerCannotHandlePipelinedRequestsReliably;
- (BOOL)serverCannotHandlePipelinedRequestsReliably;
- (BOOL)shouldPipelineRequests;
- (NSUInteger)maximumNumberOfRequestsToPipeline;

@end
