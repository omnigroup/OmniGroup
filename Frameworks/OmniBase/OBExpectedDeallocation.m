// Copyright 1997-2008, 2011,2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBExpectedDeallocation.h>

#import <OmniBase/assertions.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>
#import <execinfo.h>

RCS_ID("$Id$")

#ifdef DEBUG

#define DEBUG_EXPECTED_DEALLOCATIONS 0
#if DEBUG_EXPECTED_DEALLOCATIONS
    #define LOG(format, ...) NSLog(@"DEALLOC: " format, ## __VA_ARGS__)
#else
    #define LOG(format, ...) do {} while(0)
#endif

@interface _OBExpectedDeallocation : NSObject
- initWithObject:(__unsafe_unretained id)object;
@end

@implementation _OBExpectedDeallocation
{
    __unsafe_unretained id _object;
    Class _originalClass;
    CFAbsoluteTime _originalTime;
    NSArray *_backtraceFrames;
}

static dispatch_queue_t WarningQueue;
static CFMutableArrayRef PendingDeallocations = NULL;
static NSTimer *WarningTimer = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    WarningQueue = dispatch_queue_create("com.omnigroup.OmniBase.ExpectedDeallocation", DISPATCH_QUEUE_SERIAL);
    PendingDeallocations = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL); // non-retaining
}

- initWithObject:(__unsafe_unretained id)object;
{
    if (!(self = [super init]))
        return nil;
    
    _object = object;
    _originalClass = [object class];
    _originalTime = CFAbsoluteTimeGetCurrent();
    
    {
        // Could move this whole thing to OmniFoundation to use the utilities in OFBacktrace.m, but it doesn't have the exact code I want here.
        NSMutableArray *frameStrings = [[NSMutableArray alloc] init];
        void *frames[512];
        int frameCount = backtrace(frames, sizeof(frames)/sizeof(*frames));
        char **symbols = backtrace_symbols(frames, (unsigned int)frameCount);

        for (int frameIndex = 0; frameIndex < frameCount; frameIndex++) {
            NSString *frame = [[NSString alloc] initWithFormat:@"\t%p -- %s\n", frames[frameIndex], symbols[frameIndex]];
            [frameStrings addObject:frame];
        }

        if (symbols)
            free(symbols); // The individual strings don't need to be free'd.
        
        _backtraceFrames = [frameStrings copy];
    }
    
    LOG(@"Expecting <%@:%p>", NSStringFromClass(_originalClass), object);
    
    dispatch_async(WarningQueue, ^{
        if (!WarningTimer) {
            // Create the timer here so that further enqueue blocks won't, but we flip to the main queue to schedule.
            WarningTimer = [NSTimer timerWithTimeInterval:2 target:[self class] selector:@selector(_warnAboutPendingDeallocations:) userInfo:nil repeats:NO];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSRunLoop currentRunLoop] addTimer:WarningTimer forMode:NSRunLoopCommonModes];
            });
        }
        CFArrayAppendValue(PendingDeallocations, (__bridge void *)self);
    });

    return self;
}

- (void)dealloc;
{
    void *unsafeSelf = (__bridge void *)self; // Avoid retain by block.
    
    // Capture the info we will need later in the block
#if DEBUG_EXPECTED_DEALLOCATIONS
    void *object = (__bridge void *)_object;
    Class originalClass = _originalClass;
#endif
    
    dispatch_async(WarningQueue, ^{
        CFIndex warningIndex = CFArrayGetFirstIndexOfValue(PendingDeallocations, CFRangeMake(0, CFArrayGetCount(PendingDeallocations)), unsafeSelf);
        
        // Might have logged and purged the warning already
        if (warningIndex != kCFNotFound) {
            LOG(@"Actual <%@:%p>", NSStringFromClass(originalClass), object);
            CFArrayRemoveValueAtIndex(PendingDeallocations, warningIndex);
        }
    });
}

static float kExpectedWarningTimeout = 3.0;

+ (void)_warnAboutPendingDeallocations:(NSTimer *)timer;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(timer == WarningTimer);
    
    // Block enqueues while we decide whether to make a new timer
    dispatch_sync(WarningQueue, ^{
        LOG(@"Checking for missing deallocation...");
        
        WarningTimer = nil;
        
        CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
        CFIndex warningIndex = 0, warningCount = CFArrayGetCount(PendingDeallocations);
        while (warningIndex < warningCount) {
            __unsafe_unretained _OBExpectedDeallocation *warning = (__bridge _OBExpectedDeallocation *)CFArrayGetValueAtIndex(PendingDeallocations, warningIndex);
            if (currentTime - warning->_originalTime > kExpectedWarningTimeout) {
                OBInvokeAssertionFailureHandler("DEALLOC", "", __FILE__, __LINE__, @"*** Expected deallocation of <%@:%p> from:\n\t%@", NSStringFromClass(warning->_originalClass), warning->_object, [warning->_backtraceFrames componentsJoinedByString:@"\t"]);
                CFArrayRemoveValueAtIndex(PendingDeallocations, warningIndex);
                warningCount--;
            } else {
                warningIndex++;
            }
        }
        
        if (warningCount > 0) {
            WarningTimer = [NSTimer timerWithTimeInterval:2 target:[self class] selector:@selector(_warnAboutPendingDeallocations:) userInfo:nil repeats:NO];

            // We are already on the main queue
            [[NSRunLoop currentRunLoop] addTimer:WarningTimer forMode:NSRunLoopCommonModes];
        }
    });
}

@end

static unsigned DeallocationWarningKey;

void OBExpectDeallocation(id object)
{
    if (!object)
        return;
    
    if (objc_getAssociatedObject(object, &DeallocationWarningKey))
        return;
    
    _OBExpectedDeallocation *warning = [[_OBExpectedDeallocation alloc] initWithObject:object];
    objc_setAssociatedObject(object, &DeallocationWarningKey, warning, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#endif
