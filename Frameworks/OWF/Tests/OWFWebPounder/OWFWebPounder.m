// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OWF/OWF.h>

#import <Foundation/NSDate.h>

#import "OWFWebPounder.h"
#import "OWAnchorsProcessor.h"

RCS_ID("$Id$")

// #define OMNIOBJECTMETER_ENABLED

#define ACTIVE_COUNT (30)
#define COUNT_TO_START (1)
#define PROCESSORS_TO_QUEUE (2000)

// static OFMessageQueue *messageQueue;
// static NSConditionLock *startMoreLock;
static unsigned int activeCount = 0;
static unsigned int startedCount = 0;

@interface OWFWebPounderObserver : OFObject
{
    OWAddress *listenAddress;
}

+ (void)createObserversForAddressStrings:(NSArray *)addressStrings;
+ (void)createObserverForAddressString:(NSString *)addressString;
- (id)initWithAddress:(OWAddress *)anAddress;

@end

int main(int argc, char *argv[])
{
    NSMutableArray *addressStrings;
    int argumentIndex;
    
    if (argc < 2) {
        fprintf(stderr, "usage: %s [ url | delay ] ...\n", argv[0]);
        exit(1);
    }

#ifdef OMNIOBJECTMETER_ENABLED
    extern void OOMInit(void);

    OOMInit();
#endif

    OMNI_POOL_START {
        [OBPostLoader processClasses];
        [OWAnchorsProcessor class];
        [[OFController sharedController] didInitialize];
        [[OFController sharedController] startedRunning];
        [[OFScheduler dedicatedThreadScheduler] setInvokesEventsInMainThread:NO];

        addressStrings = [NSMutableArray array];
        for (argumentIndex = 1; argumentIndex < argc; argumentIndex++)
            [addressStrings addObject:[NSString stringWithCString:argv[argumentIndex]]];
        
/*
        messageQueue = [[OFMessageQueue alloc] init];
        [messageQueue startBackgroundProcessors:4];
        
        startMoreLock = [[NSConditionLock alloc] initWithCondition:YES];
        
        [OFMessageQueue setDebug:YES];
        [OWPipeline setDebug:YES];
        [OWHTTPSession setDebug:YES];
*/

        [NSThread detachNewThreadSelector:@selector(logStatus) toTarget:[OWFWebPounder class] withObject:nil];
        [NSThread detachNewThreadSelector:@selector(createFetchersForAddressStrings:) toTarget:[OWFWebPounder class] withObject:addressStrings];
//        [NSThread detachNewThreadSelector:@selector(createObserversForAddressStrings:) toTarget:[OWFWebPounderObserver class] withObject:addressStrings];
    } OMNI_POOL_END;
    
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate distantFuture]];
    
    return 0;
}

@implementation OWFWebPounder

static OFSimpleLockType statusLock;
static unsigned int processorsStarted = 0, processorsChecked = 0;
static NSLock *anchorStringsCacheLock;
static NSMutableDictionary *anchorStringsCache;

+ (void)initialize;
{
    OBINITIALIZE;

    OFSimpleLockInit(&statusLock);
    anchorStringsCacheLock = [[NSLock alloc] init];
    anchorStringsCache = [[NSMutableDictionary alloc] init];
}

+ (void)checkAnchorStrings:(NSArray *)anchorStrings fromSource:(NSString *)source;
{
    OBPRECONDITION(anchorStrings != nil);
    OBPRECONDITION(source != nil);

    OFSimpleLock(&statusLock);
    processorsChecked++;
    OFSimpleUnlock(&statusLock);

    NSArray *cachedValue;

    [anchorStringsCacheLock lock];
    cachedValue = [[anchorStringsCache objectForKey:source] retain];
    if (cachedValue == nil)
        [anchorStringsCache setObject:anchorStrings forKey:source];
    [anchorStringsCacheLock unlock];

    OBASSERT(cachedValue == nil || [anchorStrings isEqual:cachedValue]);
    [cachedValue release];
}

+ (void)createFetchersForAddressStrings:(NSMutableArray *)addressStrings;
{
    BOOL keepGoing = YES;
    unsigned int addressStringsCount = [addressStrings count];
    unsigned int loopCount = PROCESSORS_TO_QUEUE;

    do {
        OMNI_POOL_START {
            NSString *addressString;

            activeCount++;
            keepGoing = (startedCount < addressStringsCount);
            if (keepGoing) {
                addressString = [addressStrings objectAtIndex:startedCount];
                startedCount++;
                startedCount = startedCount % addressStringsCount;
                if ([addressString intValue])
                    sleep([addressString intValue]);
                else if (addressString != nil)
                    [self fetchAddressString:addressString];
                loopCount--;
                keepGoing = loopCount > 0;
            }
        } OMNI_POOL_END;
    } while (keepGoing);
}

+ (void)logStatus;
{
    BOOL continueReportingStatus = YES;
    unsigned int previousProcessorsStarted = 0;
    unsigned int previousProcessorsChecked = 0;

    do {
        OMNI_POOL_START {
            [[NSDate dateWithTimeIntervalSinceNow:1.0] sleepUntilDate];

            unsigned int startedDelta, checkedDelta;

            OFSimpleLock(&statusLock);
            started = processorsStarted;
            checked = processorsChecked;
            OFSimpleUnlock(&statusLock);

            OBASSERT(processorsStarted >= previousProcessorsStarted);
            OBASSERT(processorsChecked >= previousProcessorsChecked);
            printf("Processors started = %d (+%d), checked = %d (+%d)\n", started, started - previousProcessorsStarted, checked, checked - previousProcessorsChecked);
            previousProcessorsStarted = processorsStarted;
            previousProcessorsChecked = processorsChecked;

            [self flushCache];

            if (processorsStarted == previousProcessorsStarted)
                continueReportingStatus = NO;

        } OMNI_POOL_END;
    } while (continueReportingStatus);

    OMNI_POOL_START {
        [[NSDate dateWithTimeIntervalSinceNow:1.0] sleepUntilDate];
        NSLog(@"caches = %@", [[[OWContentCacheGroup defaultCacheGroup] caches] description]);
    } OMNI_POOL_END;
}

+ (void)flushCache;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OWContentCacheFlushNotification object:nil userInfo:[NSDictionary dictionaryWithObject:OWContentCacheFlush_Remove forKey:OWContentCacheInvalidateOrRemoveNotificationInfoKey]];
}

+ (void)fetchAddressString:(NSString *)addressString;
{
    OFSimpleLock(&statusLock);
    processorsStarted++;
    OFSimpleUnlock(&statusLock);

    static OFScheduler *scheduler = nil;

    if (scheduler == nil)
        scheduler = [[[OFScheduler dedicatedThreadScheduler] subscheduler] retain];

    OWFWebPounder *pounder = [[self alloc] initWithAddressString:addressString];
#define RELEASE_TIME 0.001
// #define RELEASE_TIME 0.1
    [scheduler scheduleSelector:@selector(self) onObject:pounder afterTime:RELEASE_TIME];
    // [pounder release];
}

- (id)initWithAddressString:(NSString *)addressString;
{
    if (!(self = [super init]))
        return nil;

    [OWWebPipeline startPipelineWithAddress:[OWAddress addressForDirtyString:addressString] target:self];

    return self;
}

//
// OWTarget
//

- (OWContentType *)targetContentType;
{
//  return [OWContentType contentTypeForString:@"text/html"];
    return [OWAnchorsProcessor anchorsContentType];
}

- (OWTargetContentDisposition)pipeline:(OWPipeline *)aPipeline hasContent:(OWContent *)someContent flags:(OWTargetContentOffer)contentFlags;
{
    OWAddress *sourceAddress = [aPipeline lastAddress];

    OWObjectStreamCursor *cursor = [someContent objectCursor];
    NSMutableArray *allAnchorStrings = [[NSMutableArray alloc] init];
    OWAddress *anchorAddress;

    while ((anchorAddress = [cursor readObject]) != nil)
        [allAnchorStrings addObject:[anchorAddress addressString]];

    [isa checkAnchorStrings:allAnchorStrings fromSource:[sourceAddress addressString]];
    
    return OWTargetContentDisposition_ContentAccepted;
}

- (OWContentInfo *)parentContentInfo;
{
    return [OWContentInfo headerContentInfoWithName:@"Anchor"];
}

- (NSString *)targetTypeFormatString;
{
    return @"Anchor";
}

//
// OWOptionalTarget informal protocol
//

- (void)pipelineDidEnd:(OWPipeline *)aPipeline;
{
#ifdef DEBUG_kc0
    NSLog(@"-[%@ %s]", OBShortObjectDescription(self), _cmd);
#endif
    [OWPipeline invalidatePipelinesForTarget:self];
    [[NSDate dateWithTimeIntervalSinceNow:0.01] sleepUntilDate];
    [self release];
}

@end

@interface OWFWebPounderObserver (Private)
- (void)_pipelineFetchedNotification:(NSNotification *)notification;
@end

@implementation OWFWebPounderObserver

+ (void)createObserversForAddressStrings:(NSArray *)addressStrings;
{
    BOOL keepGoing = YES;
    unsigned int addressStringsCount = [addressStrings count];
    unsigned int loopCount = PROCESSORS_TO_QUEUE;

    do {
        OMNI_POOL_START {
            NSString *addressString;

            activeCount++;
            keepGoing = (startedCount < addressStringsCount);
            if (keepGoing) {
                addressString = [addressStrings objectAtIndex:startedCount];
                startedCount++;
                startedCount = startedCount % addressStringsCount;
                if ([addressString intValue])
                    sleep([addressString intValue]);
                else if (addressString != nil)
                    [self createObserverForAddressString:addressString];
                loopCount--;
                keepGoing = loopCount > 0;
            }
        } OMNI_POOL_END;
    } while (keepGoing);
}

+ (void)createObserverForAddressString:(NSString *)addressString;
{
    static OFScheduler *scheduler = nil;

    if (scheduler == nil)
        scheduler = [[[OFScheduler dedicatedThreadScheduler] subscheduler] retain];

    OWFWebPounderObserver *observer = [[self alloc] initWithAddress:[OWAddress addressForDirtyString:addressString]];
    [scheduler scheduleSelector:@selector(release) onObject:observer afterTime:0.1];
}

- (id)initWithAddress:(OWAddress *)anAddress;
{
    if (!(self = [super init]))
        return nil;

    listenAddress = [anAddress retain];
    [OWPipeline addObserver:self selector:@selector(_pipelineFetchedNotification:) address:listenAddress];

    return self;
}

- (void)dealloc;
{
    [OWPipeline removeObserver:self address:listenAddress];
    [listenAddress release];
    listenAddress = nil;

    [super dealloc];
}

@end

@implementation OWFWebPounderObserver (Private)

- (void)_pipelineFetchedNotification:(NSNotification *)notification;
{
    OBASSERT([[listenAddress cacheKey] isEqualToString:[notification name]]);
    [[NSDate dateWithTimeIntervalSinceNow:0.1] sleepUntilDate];
    OBASSERT(listenAddress != nil);
}

@end
