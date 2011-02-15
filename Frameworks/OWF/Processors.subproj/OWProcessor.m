// Copyright 1997-2005, 2007, 2010-2011 Omni Development, Inc.  All rights reserved.
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

static NSMapTable *classNameToReadableNameMapTable = NULL;
static NSLock *readableNameDictionaryLock = nil;
static NSString *StatusStrings[6];
static BOOL OWProcessorTimeLog = NO;

+ (void)initialize;
{
    NSBundle *myBundle;
    
    OBINITIALIZE;

    readableNameDictionaryLock = [[NSLock alloc] init];
    classNameToReadableNameMapTable = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks, NSObjectMapValueCallBacks, 25);
    
    myBundle = [NSBundle bundleForClass:[OWProcessor class]];
    StatusStrings[OWProcessorNotStarted] = [NSLocalizedStringFromTableInBundle(@"Not Started", @"OWF", myBundle, @"processor status") retain];
    StatusStrings[OWProcessorStarting] = [NSLocalizedStringFromTableInBundle(@"Waiting", @"OWF", myBundle, @"processor status") retain];
    StatusStrings[OWProcessorQueued] = [NSLocalizedStringFromTableInBundle(@"Queued", @"OWF", myBundle, @"processor status") retain];
    StatusStrings[OWProcessorRunning] = [NSLocalizedStringFromTableInBundle(@"Running", @"OWF", myBundle, @"processor status") retain];
    StatusStrings[OWProcessorAborting] = [NSLocalizedStringFromTableInBundle(@"Stopping", @"OWF", myBundle, @"processor status") retain];
    StatusStrings[OWProcessorRetired] = [NSLocalizedStringFromTableInBundle(@"Exiting", @"OWF", myBundle, @"processor status") retain];
}

+ (NSString *)readableClassName;
{
    NSString *readableName;
    NSRange range;
    
    [readableNameDictionaryLock lock];

    readableName = NSMapGet(classNameToReadableNameMapTable, self);
    if (readableName)
	goto unlockAndReturn;
    
    NSString *className = NSStringFromClass(self);
    
    if ((range = [className rangeOfString:@"Omni" options:NSAnchoredSearch]).length || (range = [className rangeOfString:@"OW" options:NSAnchoredSearch]).length)
	readableName = [className substringFromIndex:NSMaxRange(range)];
    else
	readableName = className;
	
    if ((range = [readableName rangeOfString:@"Processor" options:NSAnchoredSearch|NSBackwardsSearch]).length)
	readableName = [readableName substringToIndex:range.location];
    
    NSMapInsert(classNameToReadableNameMapTable, self, readableName);
	
unlockAndReturn:
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
        NSInteger threadCount;

        threadCount = [[NSUserDefaults standardUserDefaults] integerForKey:@"OWProcessorThreadCount"];
        if (threadCount <= 0)
            threadCount = 12;
#if defined(DEBUG_kc) || defined(DEBUG_wiml)
        NSLog(@"OWProcessor: Using %d threads", threadCount);
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
    if (![super init])
	return nil;
    
    OFSimpleLockInit(&displayablesSimpleLock);
    [self setStatus:OWProcessorStarting];

    pipeline = [aPipeline retain];
    originalContent = [initialContent retain];

    return self;
}

- (void)dealloc;
{
    OFSimpleLockFree(&displayablesSimpleLock);
    [statusString release];
    [pipeline release];
    [originalContent release];
    [super dealloc];
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
    [self startProcessingInQueue:[isa processorQueue]];
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
    OFSimpleLock(&displayablesSimpleLock);
    [statusString release];
    statusString = [newStatus retain];
    OFSimpleUnlock(&displayablesSimpleLock);
    [pipeline processorStatusChanged:self];
}

- (void)setStatusFormat:(NSString *)aFormat, ...;
{
    NSString *newStatus;
    va_list argList;

    va_start(argList, aFormat);
    newStatus = [[NSString alloc] initWithFormat:aFormat arguments:argList];
    va_end(argList);
    [self setStatusString:newStatus];
    [newStatus release];
}

- (void)setStatusStringWithClassName:(NSString *)newStatus;
{
    NSMutableString *newStatusString;

    // Avoid +stringWithFormat: since this is simple
    newStatusString = [[NSMutableString alloc] initWithString: [isa readableClassName]];
    [newStatusString appendString: @" "];
    [newStatusString appendString: newStatus];
    
    [self setStatusString: newStatusString];
    [newStatusString release];
}

- (NSString *)statusString;
{
    NSString *aStatus;

    OFSimpleLock(&displayablesSimpleLock);
    aStatus = [[statusString retain] autorelease];
    OFSimpleUnlock(&displayablesSimpleLock);
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
        return (OFMessageQueueSchedulingInfo){.priority = OFLowPriority, .group = [OWProcessor class], .maximumSimultaneousThreadsInGroup = 1};
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
    NSAutoreleasePool *pool;
    
    if (status == OWProcessorAborting) {
        [self retire];
        return;
    }
    pool = [[NSAutoreleasePool alloc] init];
    NS_DURING {
        [self processBegin];
        [pool release];
        
        pool = [[NSAutoreleasePool alloc] init];
        [self process];
        [pool release];
        
        pool = [[NSAutoreleasePool alloc] init];
        [self processEnd];
    } NS_HANDLER {
        if (status != OWProcessorAborting)
            [self handleProcessingException:localException];
        [self processAbort];
    } NS_ENDHANDLER;
    [pool release];
    [self retire];
}

- (void)retire;
{
    [self setStatus:OWProcessorRetired];
    [pipeline processorDidRetire:self];
}

- (void)handleProcessingException:(NSException *)processingException;
{
    OWContent *errorContent;
    BOOL alreadyHadError;

    alreadyHadError = [pipeline hadError];

    if ([[processingException name] isEqualToString:@"OWProcessorCacheArcHasRetired"]) {
        [pipeline noteErrorName:[processingException displayName] reason:[processingException reason]];
        return;
    }

    NSLog(@"%@ (%@): %@: %@", [[pipeline contextObjectForKey:OWCacheArcSourceURLKey] compositeString], [isa readableClassName], [processingException displayName], [processingException reason]);

    [pipeline noteErrorName:[processingException displayName] reason:[processingException reason]];

    if (alreadyHadError)
        return;

    errorContent = [OWContent contentWithConcreteCacheEntry:processingException];
    
    [pipeline addContent:errorContent fromProcessor:self flags:OWProcessorContentIsError | OWProcessorTypeRetrieval];
}
    
- (OWFileInfo *)cacheDate:(NSDate *)aDate forAddress:(OWAddress *)anAddress
{
    OWContent *newContent;
    OWFileInfo *fileInfo;

    fileInfo = [[OWFileInfo alloc] initWithLastChangeDate:aDate];
    newContent = [[OWContent alloc] initWithContent:fileInfo];
    [fileInfo release];
    [newContent markEndOfHeaders];
    [newContent autorelease];
    [pipeline extraContent:newContent fromProcessor:self forAddress:anAddress];
    return fileInfo;
}


// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:[(id)pipeline shortDescription] forKey:@"pipeline"];
    if (statusString)
        [debugDictionary setObject:[self statusString] forKey:@"statusString"];

    return debugDictionary;
}

@end

