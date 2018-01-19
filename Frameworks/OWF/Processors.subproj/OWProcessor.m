// Copyright 1997-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/NSException-OWConcreteCacheEntry.h>
#import <OWF/OWContent.h>
#import <OWF/OWContentInfo.h>
#import <OWF/OWContentType.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWFileInfo.h>
#import <OWF/OWObjectStream.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWProcessorDescription.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")

@implementation OWProcessor
{
    __weak id <OWProcessorContext> pipeline;
    
    // For display purposes
    os_unfair_lock displayablesLock;
    OWProcessorStatus status;
    NSString *statusString;
}

static NSMapTable *classNameToReadableNameMapTable = NULL;
static NSLock *readableNameDictionaryLock = nil;
static NSString *StatusStrings[6];
static BOOL OWProcessorTimeLog = NO;

+ (void)initialize;
{
    OBINITIALIZE;

    readableNameDictionaryLock = [[NSLock alloc] init];
    classNameToReadableNameMapTable = [NSMapTable weakToStrongObjectsMapTable];
    
    StatusStrings[OWProcessorNotStarted] = NSLocalizedStringFromTableInBundle(@"Not Started", @"OWF", OMNI_BUNDLE, @"processor status");
    StatusStrings[OWProcessorStarting] = NSLocalizedStringFromTableInBundle(@"Waiting", @"OWF", OMNI_BUNDLE, @"processor status");
    StatusStrings[OWProcessorQueued] = NSLocalizedStringFromTableInBundle(@"Queued", @"OWF", OMNI_BUNDLE, @"processor status");
    StatusStrings[OWProcessorRunning] = NSLocalizedStringFromTableInBundle(@"Running", @"OWF", OMNI_BUNDLE, @"processor status");
    StatusStrings[OWProcessorAborting] = NSLocalizedStringFromTableInBundle(@"Stopping", @"OWF", OMNI_BUNDLE, @"processor status");
    StatusStrings[OWProcessorRetired] = NSLocalizedStringFromTableInBundle(@"Exiting", @"OWF", OMNI_BUNDLE, @"processor status");
}

+ (NSString *)readableClassName;
{
    [readableNameDictionaryLock lock];

    NSString *readableName = [classNameToReadableNameMapTable objectForKey:self];
    if (readableName == nil) {
        NSString *className = NSStringFromClass(self);
        
        NSRange range;
        if ((range = [className rangeOfString:@"Omni" options:NSAnchoredSearch]).length || (range = [className rangeOfString:@"OW" options:NSAnchoredSearch]).length)
            readableName = [className substringFromIndex:NSMaxRange(range)];
        else
            readableName = className;
        
        if ((range = [readableName rangeOfString:@"Processor" options:NSAnchoredSearch|NSBackwardsSearch]).length)
            readableName = [readableName substringToIndex:range.location];
        
        [classNameToReadableNameMapTable setObject:readableName forKey:self];
    }
	
    [readableNameDictionaryLock unlock];
    return readableName;
}

+ (BOOL)processorUsesNetwork
{
    return NO;
}

+ (OFMessageQueue *)processorQueue;
{
    static OFMessageQueue *processorQueue = nil;

    if (processorQueue == nil) {
        NSInteger threadCount = [[NSUserDefaults standardUserDefaults] integerForKey:@"OWProcessorThreadCount"];
        if (threadCount <= 0)
            threadCount = 12;
#if defined(DEBUG_kc) || defined(DEBUG_wiml)
        NSLog(@"OWProcessor: Using %ld threads", threadCount);
#endif
        processorQueue = [[OFMessageQueue alloc] init];
        [processorQueue startBackgroundProcessors:threadCount];
    }
    return processorQueue;
}

+ (void)registerProcessorClass:(Class)aClass fromContentType:(OWContentType *)sourceContentType toContentType:(OWContentType *)targetContentType cost:(float)aCost producingSource:(BOOL)producingSource;
{
    OWProcessorDescription *description;
    
    description = [OWProcessorDescription processorDescriptionForProcessorClassName: NSStringFromClass(aClass)];
    [description setUsesNetwork:[aClass processorUsesNetwork]];
    [description registerProcessesContentType: sourceContentType toContentType:targetContentType cost:aCost producingSource:producingSource];
}

+ (void)registerProcessorClass:(Class)aClass fromContentTypeString:(NSString *)sourceContentTypeString toContentTypeString:(NSString *)targetContentTypeString cost:(float)aCost producingSource:(BOOL)producingSource;
{
    OWContentType *sourceContentType, *targetContentType;

    sourceContentType = [OWContentType contentTypeForString:sourceContentTypeString];
    targetContentType = [OWContentType contentTypeForString:targetContentTypeString];
    [self registerProcessorClass:aClass fromContentType:sourceContentType toContentType:targetContentType cost:aCost producingSource:producingSource];
}

// OFBundleRegistryTarget informal protocol

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)description;
{
#warning TJW: Should we just allow you to put your dictionary under OWProcessor or OWProcessorDescription or should we put a log message here?
//    NSLog(@"OWProcessorDescription should be registered instead of OWProcessor in bundle %@ itemName %@ description %@", bundle, itemName, description);
    [OWProcessorDescription registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)description];
}

// Init and dealloc

- init;
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;
{
    if (!(self = [super init]))
	return nil;
    
    displayablesLock = OS_UNFAIR_LOCK_INIT;
    [self setStatus:OWProcessorStarting];

    pipeline = aPipeline;
    originalContent = initialContent;

    return self;
}

//

- (id <OWProcessorContext>)pipeline;
{
    return pipeline;
}

// Processing

- (void)startProcessingInQueue:(OFMessageQueue *)aQueue;
{
    if (status == OWProcessorAborting) {
	[self retire];
	return;
    }
    [self setStatus:OWProcessorQueued];
    if (aQueue != nil)
        [aQueue queueSelector:@selector(processInThread) forObject:self];
    else
        [self processInThread];
}

- (void)startProcessing;
{
    [self startProcessingInQueue:[[self class] processorQueue]];
}

- (void)abortProcessing;
{
    [self setStatus:OWProcessorAborting];
}


// Status

- (void)setStatus:(OWProcessorStatus)newStatus;
{
    if (status == newStatus)
        return;
    status = newStatus;
    [self setStatusStringWithClassName:StatusStrings[status]];
}

- (OWProcessorStatus)status;
{
    return status;
}

- (void)setStatusString:(NSString *)newStatus;
{
    if (statusString == newStatus)
	return;
    os_unfair_lock_lock(&displayablesLock);
    statusString = newStatus;
    os_unfair_lock_unlock(&displayablesLock);
    [pipeline processorStatusChanged:self];
}

- (void)setStatusFormat:(NSString *)aFormat, ...;
{
    va_list argList;
    va_start(argList, aFormat);
    NSString *newStatus = [[NSString alloc] initWithFormat:aFormat arguments:argList];
    va_end(argList);
    [self setStatusString:newStatus];
}

- (void)setStatusStringWithClassName:(NSString *)newStatus;
{
    // Avoid +stringWithFormat: since this is simple
    NSMutableString *newStatusString = [[NSMutableString alloc] initWithString:[[self class] readableClassName]];
    [newStatusString appendString:@" "];
    [newStatusString appendString:newStatus];
    
    [self setStatusString:newStatusString];
}

- (NSString *)statusString;
{
    os_unfair_lock_lock(&displayablesLock);
    NSString *aStatus = statusString;
    os_unfair_lock_unlock(&displayablesLock);
    return aStatus;
}

- (void)processedBytes:(NSUInteger)bytes;
{
    [self processedBytes:bytes ofBytes:NSNotFound];
}

- (void)processedBytes:(NSUInteger)bytes ofBytes:(NSUInteger)newTotalBytes;
{
    [pipeline processedBytes:bytes ofBytes:newTotalBytes];
}

- (NSDate *)firstBytesDate;
{
    return [pipeline firstBytesDate];
}

- (NSUInteger)bytesProcessed;
{
    return [pipeline bytesProcessed];
}

- (NSUInteger)totalBytes;
{
    return [pipeline totalBytes];
}

// OFMessageQueuePriority protocol

- (OFMessageQueueSchedulingInfo)messageQueueSchedulingInfo;
{
    if (pipeline != nil) {
        return [pipeline messageQueueSchedulingInfo];
    } else {
        return (OFMessageQueueSchedulingInfo){.priority = OFLowPriority, .group = (__bridge const void *)([OWProcessor class]), .maximumSimultaneousThreadsInGroup = 1};
    }
}

@end


@implementation OWProcessor (SubclassesOnly)

- (void)processBegin;
{
    [self setStatus:OWProcessorRunning];
    if (OWProcessorTimeLog)
        NSLog(@"%@: begin", [self shortDescription]);
}

- (void)process;
{
}

- (void)processEnd;
{
    if (OWProcessorTimeLog)
        NSLog(@"%@: end", [self shortDescription]);
}

- (void)processAbort;
{
}

// Stuff only used by OWProcessor, or by subclasses which don't want to start a subthread

- (void)processInThread;
{
    if (status == OWProcessorAborting) {
        [self retire];
        return;
    }

    @try {
        @autoreleasepool {
            [self processBegin];
        }
        
        @autoreleasepool {
            [self process];
        }
        
        @autoreleasepool {
            [self processEnd];
        }
    } @catch (NSException *localException) {
        @autoreleasepool {
            if (status != OWProcessorAborting)
                [self handleProcessingException:localException];
            [self processAbort];
        }
    } @finally {
        [self retire];
    }
}

- (void)retire;
{
    [self setStatus:OWProcessorRetired];
    [pipeline processorDidRetire:self];
}

- (void)handleProcessingException:(NSException *)processingException;
{
    BOOL alreadyHadError = [pipeline hadError];

    if ([[processingException name] isEqualToString:@"OWProcessorCacheArcHasRetired"]) {
        [pipeline noteErrorName:[processingException displayName] reason:[processingException reason]];
        return;
    }

    NSLog(@"%@ (%@): %@: %@", [[pipeline contextObjectForKey:OWCacheArcSourceURLKey] compositeString], [[self class] readableClassName], [processingException displayName], [processingException reason]);

    [pipeline noteErrorName:[processingException displayName] reason:[processingException reason]];

    if (alreadyHadError)
        return;

    OWContent *errorContent = [OWContent contentWithConcreteCacheEntry:processingException];
    [pipeline addContent:errorContent fromProcessor:self flags:OWProcessorContentIsError | OWProcessorTypeRetrieval];
}
    
- (OWFileInfo *)cacheDate:(NSDate *)aDate forAddress:(OWAddress *)anAddress
{
    OWFileInfo *fileInfo = [[OWFileInfo alloc] initWithLastChangeDate:aDate];
    OWContent *newContent = [[OWContent alloc] initWithContent:fileInfo];
    [newContent markEndOfHeaders];
    [pipeline extraContent:newContent fromProcessor:self forAddress:anAddress];
    return fileInfo;
}


// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    [debugDictionary setObject:[(id)pipeline shortDescription] forKey:@"pipeline"];
    if (statusString)
        [debugDictionary setObject:[self statusString] forKey:@"statusString"];

    return debugDictionary;
}

@end

