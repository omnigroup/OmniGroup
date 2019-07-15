// Copyright 2005-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSArray, NSData, NSDictionary, NSError, NSInputStream, NSOutputStream, NSStream, NSRunLoop;

typedef void (^OFFilterProcessFdAcceptor)(int fd);
/* If OFFilterProcessInputBlockKey is set, it must be a block of type OFFilterProcessFdAcceptor. It is called once with the file descriptor opened to which the child's stdin should be written. It's the acceptor's responsibility to schedule further asynchronous activity if needed, close the descriptor when done, etc. */

@interface OFFilterProcess : NSObject

/* Keys for the parameters dictionary */
#define OFFilterProcessCommandPathKey               (@"command")     /* NSString */
#define OFFilterProcessArgumentsKey                 (@"argv")        /* NSArray of NSStrings */
#define OFFilterProcessWorkingDirectoryPathKey      (@"chdir")       /* NSString */
#define OFFilterProcessInputDataKey                 (@"input-data")  /* NSData */
/* #define OFFilterProcessInputDataKey              (@"input-stream")  NSStream is too buggy to implement this yet (RADAR 5177472 / 5177598) */
#define OFFilterProcessInputBlockKey                (@"input-writer")  /* OFFilterProcessFdAcceptor block */
#define OFFilterProcessReplacementEnvironmentKey    (@"envp")        /* NSDictionary of NSString->NSString or NSData */
#define OFFilterProcessAdditionalEnvironmentKey     (@"setenv")      /* NSDictionary of NSString->NSString or NSData */
#define OFFilterProcessAdditionalPathEntryKey       (@"+PATH")       /* NSString */
#define OFFilterProcessDetachTTYKey                 (@"detach")      /* NSNumber, defaults to TRUE */
#define OFFilterProcessNewProcessGroupKey           (@"setpgrp")     /* NSNumber, defaults to FALSE */

/* Init actually creates and starts the task */
- initWithParameters:(NSDictionary *)filterParameters standardOutput:(NSOutputStream *)stdoutStream standardError:(NSOutputStream *)stderrStream;

// Can be used to free up operating system resources as early as possible. Automatically called when the object is deallocated/finalized.
- (void)invalidate;

@property(nonatomic,readonly) NSString *commandPath;    // Constant
@property(nonatomic,readonly) NSArray  *arguments;      // Constant

@property(nonatomic,readonly) NSError *error;           // KVO-compliant
@property(nonatomic,readonly) BOOL isRunning;           // KVO-compliant

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

// BOOL OFIncludeInPathEnvironment(const char *pathdir) // Not used right now. Uncomment if you need it.

