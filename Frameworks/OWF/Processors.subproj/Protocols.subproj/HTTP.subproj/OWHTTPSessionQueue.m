// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWHTTPSessionQueue.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWAddress.h>
#import <OWF/OWContentCacheProtocols.h>
#import <OWF/OWHTTPProcessor.h>
#import <OWF/OWHTTPSession.h>
#import <OWF/OWNetLocation.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")

@interface OWHTTPSessionQueue (Private)
+ (void)_contentCacheFlushedNotification:(NSNotification *)notification;
+ (void)_lockedCleanSessionQueuesOlderThanTimeoutExcludingQueue:(OWHTTPSessionQueue *)excludedQueue;
+ (void)_lockedFlushSessionQueuesOlderThanDate:(NSDate *)aDate excludingQueue:(OWHTTPSessionQueue *)excludedQueue;
- (NSArray *)_queuedProcessorsSnapshot;
@end

@implementation OWHTTPSessionQueue

static OFDatedMutableDictionary *queues;
static NSLock *queueLock;
static NSTimeInterval sessionTimeout;

+ (void)initialize;
{
    static BOOL initialized = NO;

    [super initialize];

    // We want to flush our subclasses' caches, too.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_contentCacheFlushedNotification:) name:OWContentCacheFlushNotification object:nil];

    if (initialized)
        return;
    initialized = YES;

    sessionTimeout = [[NSUserDefaults standardUserDefaults] floatForKey:@"OWHTTPSessionTimeout"];
    queues = [[OFDatedMutableDictionary alloc] init];
    queueLock = [[NSLock alloc] init];
}

+ (OWHTTPSessionQueue *)httpSessionQueueForAddress:(OWAddress *)anAddress;
{
    OWHTTPSessionQueue *queue;

    @autoreleasepool {
        OFDatedMutableDictionary *cache = [self cache];
        NSString *cacheKey = [self cacheKeyForSessionQueueForAddress:anAddress];
        OBASSERT(cacheKey != nil);
        
        [queueLock lock];
        
        // Lookup the queue for this address, creating if neccesary
        queue = [cache objectForKey:cacheKey];
        if (queue == nil) {
            queue = [[self alloc] initWithAddress:anAddress];
            [cache setObject:queue forKey:cacheKey];
        }
        [self _lockedCleanSessionQueuesOlderThanTimeoutExcludingQueue:queue];
        
        [queueLock unlock];
    }

    return queue;
}

+ (NSString *)cacheKeyForSessionQueueForAddress:(OWAddress *)anAddress;
{
    NSString *cacheKey;
    
    cacheKey = [[anAddress proxyURL] netLocation];
    return cacheKey != nil ? cacheKey : @""; // The URL "http:/" has a nil netLocation, and nil cacheKeys cause exceptions while updating the locked cache dictionary (since dictionary keys can't be nil), leading to hangs
}

+ (Class)sessionClass;
{
    return [OWHTTPSession class];
}

+ (OFDatedMutableDictionary *)cache;
{
    // This is subclassed by the HTTPS plug-in which has its own cache
    return queues;
}

+ (NSUInteger)maximumSessionsPerServer;
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"OWHTTPMaximumSessionsPerServer"];
}


- initWithAddress:(OWAddress *)anAddress;
{
    if (!(self = [super init]))
        return nil;

    address = anAddress;
    idleSessions = [[NSMutableArray alloc] init];
    sessions = [[NSMutableArray alloc] init];
    queuedProcessors = [[NSMutableArray alloc] init];
    abortedProcessors = [[NSMutableSet alloc] init];
    lock = [[NSLock alloc] init];
    flags.serverUnderstandsPipelinedRequests = NO;
    flags.serverCannotHandlePipelinedRequestsReliably = NO;

    return self;
}

- (BOOL)queueProcessor:(OWHTTPProcessor *)aProcessor;
{
    BOOL result;
    NSInteger runningSessions;
    
    [lock lock];
    if ([abortedProcessors member:aProcessor]) {
        [abortedProcessors removeObject:aProcessor];
        result = NO;
    } else {
        [queuedProcessors addObject:aProcessor];
        runningSessions = [sessions count] - [idleSessions count];
        result = (runningSessions < (NSInteger)[[self class] maximumSessionsPerServer]);
    }
    [lock unlock];

    return result;
}

- (void)runSession;
{
    OWHTTPSession *session;
    
    [lock lock];
    if ([queuedProcessors count]) {
        if ([idleSessions count]) {
            session = [idleSessions lastObject];
            [idleSessions removeLastObject];
        } else {
            session = [[[[self class] sessionClass] alloc] initWithAddress:address inQueue:self];
            [sessions addObject:session];
        }
    } else
        session = nil;
    [lock unlock];

    [session runSession];
}

- (void)abortProcessingForProcessor:(OWHTTPProcessor *)aProcessor;
{
    NSUInteger index;
    NSArray *temporaryArray;
    
    [lock lock];
    if ((index = [queuedProcessors indexOfObject:aProcessor]) == NSNotFound) {
        [abortedProcessors addObject:aProcessor];
        temporaryArray = [NSArray arrayWithArray:sessions];
        [lock unlock];
        [temporaryArray makeObjectsPerformSelector:@selector(abortProcessingForProcessor:) withObject:aProcessor];
    } else {
        [queuedProcessors removeObjectAtIndex:index];
        [lock unlock];
    }
    [aProcessor retire];
}

- (OWHTTPProcessor *)nextProcessor;
{
    OWHTTPProcessor *result;

    [lock lock];
    if ([queuedProcessors count]) {
        result = [queuedProcessors objectAtIndex:0];
        [queuedProcessors removeObjectAtIndex:0];
    } else {
        result = nil;
    }
    [lock unlock];

    return result;
}

- (OWHTTPProcessor *)anyProcessor;
{
    OWHTTPProcessor *result;

    [lock lock];
    if ([queuedProcessors count]) {
        result = [queuedProcessors objectAtIndex:0];
    } else {
        result = nil;
    }
    [lock unlock];

    return result;
}

- (BOOL)sessionIsIdle:(OWHTTPSession *)session;
{
    BOOL isReallyIdle;
    
    [lock lock];
    isReallyIdle = [queuedProcessors count] == 0;
    if (isReallyIdle)
        [idleSessions addObject:session];
    [lock unlock];

    return isReallyIdle;
}

- (void)session:(OWHTTPSession *)session hasStatusString:(NSString *)statusString;
{
    [[self _queuedProcessorsSnapshot] makeObjectsPerformSelector:@selector(setStatusString:) withObject:statusString];
}

- (BOOL)queueEmptyAndAllSessionsIdle;
{
    BOOL result;

    [lock lock];
    result = ([queuedProcessors count] == 0) && ([idleSessions count] == [sessions count]);
    [lock unlock];

    return result;    
}

- (NSString *)queueKey;
{
    return [[self class] cacheKeyForSessionQueueForAddress:address];
}

- (void)setServerUnderstandsPipelinedRequests;
{
    flags.serverUnderstandsPipelinedRequests = YES;
}

- (BOOL)serverUnderstandsPipelinedRequests;
{
    return flags.serverUnderstandsPipelinedRequests;
}

- (void)setServerCannotHandlePipelinedRequestsReliably;
{
    flags.serverCannotHandlePipelinedRequestsReliably = YES;
}

- (BOOL)serverCannotHandlePipelinedRequestsReliably;
{
    return flags.serverCannotHandlePipelinedRequestsReliably;
}

- (BOOL)shouldPipelineRequests;
{
    return flags.serverUnderstandsPipelinedRequests && !flags.serverCannotHandlePipelinedRequestsReliably && [[NSUserDefaults standardUserDefaults] boolForKey:@"OWHTTPEnablePipelinedRequests"];
}

- (NSUInteger)maximumNumberOfRequestsToPipeline;
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"OWHTTPMaximumNumberOfRequestsToPipeline"];
}

@end

@implementation OWHTTPSessionQueue (Private)

+ (void)_contentCacheFlushedNotification:(NSNotification *)notification;
{
    // When the content cache is flushed, flush all cached HTTP sessions
    [queueLock lock];
    NS_DURING {
        [self _lockedFlushSessionQueuesOlderThanDate:nil excludingQueue:nil];
    } NS_HANDLER {
        NSLog(@"+[%@ %@]: caught exception %@", NSStringFromClass(self), NSStringFromSelector(_cmd), localException);
    } NS_ENDHANDLER;
    [queueLock unlock];
}

+ (void)_lockedCleanSessionQueuesOlderThanTimeoutExcludingQueue:(OWHTTPSessionQueue *)excludedQueue;
{
    static NSDate *lastCleanDate = nil;

    // TODO: lastCleanDate is local to this class, but we need to clean up the HTTPS cache also.  Maybe we should just have a single cache with modified keys for each protocol, rather than maintaining separate caches.
    NSDate *currentDate = [[NSDate alloc] init];
    if (lastCleanDate != nil && [currentDate timeIntervalSinceDate:lastCleanDate] < sessionTimeout) {
        return;
    }

    [self _lockedFlushSessionQueuesOlderThanDate:[NSDate dateWithTimeIntervalSinceNow:-sessionTimeout] excludingQueue:excludedQueue];
    lastCleanDate = currentDate;
}

+ (void)_lockedFlushSessionQueuesOlderThanDate:(NSDate *)aDate excludingQueue:(OWHTTPSessionQueue *)excludedQueue;
{
    OWHTTPSessionQueue *aQueue;

    if (!aDate)
        aDate = [NSDate distantFuture];
    OFDatedMutableDictionary *cache = [self cache];
    NSEnumerator *enumerator = [[cache objectsOlderThanDate:aDate] objectEnumerator];
    while ((aQueue = [enumerator nextObject])) {
        if (aQueue != excludedQueue && [aQueue queueEmptyAndAllSessionsIdle]) {
            [cache removeObjectForKey:[aQueue queueKey]];
        }
    }
}

- (NSArray *)_queuedProcessorsSnapshot;
{
    [lock lock];
    NSArray *snapshot = [[NSArray alloc] initWithArray:queuedProcessors];
    [lock unlock];
    return snapshot;
}

@end
