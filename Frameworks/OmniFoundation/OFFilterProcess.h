// Copyright 2005-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#include <sys/event.h>

@class NSArray, NSData, NSDictionary, NSError, NSInputStream, NSOutputStream, NSStream;

@interface OFFilterProcess : OFObject
{
    /* Parameters set before launch */
    NSString *commandPath;
    NSArray *arguments;
    NSData *subprocStdinBytes;
    
    /* Set at launch time */
    int subprocStdinFd;
    NSUInteger subprocStdinBytesWritten;
    
    struct copy_out_state {
        int fd;
        char *buffer;
        size_t buffer_contents_start, buffer_contents_length, buffer_size;
        NSOutputStream *nsstream;
        BOOL filterEnabled, streamReady;
    } stdoutCopyBuf, stderrCopyBuf;    
    
    pid_t child;
    
    int kevent_fd;
    CFFileDescriptorRef kevent_cf; // Lazily created
    CFRunLoopSourceRef kevent_cfrunloop;
    CFRunLoopTimerRef poll_timer; // Workaround for RADAR 6898524
#define OFFilterProcess_CHANGE_QUEUE_MAX 5
    struct kevent pending_changes[OFFilterProcess_CHANGE_QUEUE_MAX];
    int num_pending_changes;

    /* Misc state variables */
    enum {
        OFFilterProcess_Initial,
        OFFilterProcess_Started,
        OFFilterProcess_Finished
    } state;
    NSError *error;
    struct rusage child_rusage;
}

/* Keys for the parameters dictionary */
#define OFFilterProcessCommandPathKey               (@"command")     /* NSString */
#define OFFilterProcessArgumentsKey                 (@"argv")        /* NSArray of NSStrings */
#define OFFilterProcessWorkingDirectoryPathKey      (@"chdir")       /* NSString */
#define OFFilterProcessInputDataKey                 (@"input-data")  /* NSData */
/* #define OFFilterProcessInputDataKey              (@"input-stream")  NSStream is too buggy to implement this yet (RADAR 5177472 / 5177598) */
#define OFFilterProcessReplacementEnvironmentKey    (@"envp")        /* NSDictionary of NSString->NSString or NSData */
#define OFFilterProcessAdditionalEnvironmentKey     (@"setenv")      /* NSDictionary of NSString->NSString or NSData */
#define OFFilterProcessAdditionalPathEntryKey       (@"+PATH")       /* NSString */
#define OFFilterProcessDetachTTYKey                 (@"detach")      /* NSNumber, defaults to TRUE */
#define OFFilterProcessNewProcessGroupKey           (@"setpgrp")     /* NSNumber, defaults to FALSE */

/* Init actually creates and starts the task */
- initWithParameters:(NSDictionary *)filterParameters standardOutput:(NSOutputStream *)stdoutStream standardError:(NSOutputStream *)stderrStream;

@property (readonly) NSString *commandPath;    // Constant
@property (readonly) NSArray  *arguments;      // Constant

@property (readonly) NSError *error;           // KVO-compliant
@property (readonly) BOOL isRunning;           // KVO-compliant

- (void)run;  // NOTE: Unlike NSTask, this does not invoke the run loop!

/* If you want a runloop-based filter, use these */
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;

/* Convenience method. If stdoutStreamData and stderrStreamData are the same address, stdout and stderr will be merged. If runLoopMode is nil, then it will run without using the runloop. Returns YES on success, NO on failure, or propagates an exception if one occurs in the run loop. */
+ (BOOL)runWithParameters:(NSDictionary *)filterParameters inMode:(NSString *)runLoopMode standardOutput:(NSData **)stdoutStreamData standardError:(NSData **)stderrStreamData error:(NSError **)errorPtr;

@end

@interface NSData (OFFilterProcess)

- (NSData *)filterDataThroughCommandAtPath:(NSString *)commandPath withArguments:(NSArray *)arguments includeErrorsInOutput:(BOOL)includeErrorsInOutput errorStream:(NSOutputStream *)errorStream error:(NSError **)outError;
- (NSData *)filterDataThroughCommandAtPath:(NSString *)commandPath withArguments:(NSArray *)arguments includeErrorsInOutput:(BOOL)includeErrorsInOutput error:(NSError **)outError;
- (NSData *)filterDataThroughCommandAtPath:(NSString *)commandPath withArguments:(NSArray *)arguments error:(NSError **)outError;

@end

NSString *OFDescribeKevent(const struct kevent *ev);

// BOOL OFIncludeInPathEnvironment(const char *pathdir) // Not used right now. Uncomment if you need it.

