// Copyright 2005-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFFilterProcess.h>

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/NSStream.h>

#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniBase/NSError-OBExtensions.h>

#include <sys/pipe.h>
#include <crt_externs.h>

RCS_ID("$Id$")

@interface OFFilterProcess (Private)

enum handleKeventsHow {
    keventJustPush = -1,
    keventProcessButDontBlock = 0,
    keventBlockUntilActivity = 1
};

- (BOOL)_waitpid;
- (void)_pushq:(int)ident filter:(short)evfilter flags:(unsigned short)flags;
- (int)_handleKevents:(enum handleKeventsHow)flag;
- (void)_setError:(NSError *)err;

static void init_copyout(struct copy_out_state *into, int fd, NSOutputStream *stream);
static void clear_copyout(struct copy_out_state *into);
static void free_copyout(struct copy_out_state *into);
static void copy_from_subprocess(const struct kevent *ev, struct copy_out_state *into, OFFilterProcess *self);
static void copy_to_stream(struct copy_out_state *into, OFFilterProcess *self);
static void keventRunLoopCallback(CFFileDescriptorRef f, CFOptionFlags callBackTypes, void *info);
static void pollTimerRunLoopCallback(CFRunLoopTimerRef timer, void *info);

static char **computeToolEnvironment(NSDictionary *envp, NSDictionary *setenv, NSString *ensurePath);
static void freeToolEnvironment(char **envp);
static char *makeEnvEntry(id key, size_t *sepindex, id value);
static char *pathStringIncludingDirectory(const char *currentPath, const char *pathdir, const char *sep);

@end

@implementation OFFilterProcess

@synthesize commandPath, arguments, error;

struct OFPipe {
    int read, write;
};

static BOOL OFPipeCreate(struct OFPipe *p, NSError **outError)
{
    int pipeFD[2];
    if (pipe(pipeFD) != 0) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Error creating pipe", @"OmniFoundation", OMNI_BUNDLE, @"error description");
        OBErrorWithErrno(outError, OMNI_ERRNO(), "pipe()", nil, description);
        return NO;
    }
    
    p->read = pipeFD[0];
    p->write = pipeFD[1];
    return YES;
}

static void OFPipeCloseRead(struct OFPipe *p)
{
    if (p->read != -1) {
        close(p->read);
        p->read = -1;
    }
}

static void OFPipeCloseWrite(struct OFPipe *p)
{
    if (p->write != -1) {
        close(p->write);
        p->write = -1;
    }
}

static void OFPipeClose(struct OFPipe *p)
{
    OFPipeCloseRead(p);
    OFPipeCloseWrite(p);
}


- initWithParameters:(NSDictionary *)filterParameters standardOutput:(NSOutputStream *)stdoutStream standardError:(NSOutputStream *)stderrStream;
{
    self = [super init];
    
    /* Instance variables initialized from the parameters dictionary */
    commandPath = [[filterParameters objectForKey:OFFilterProcessCommandPathKey] copy];
    arguments = [[filterParameters objectForKey:OFFilterProcessArgumentsKey] copy];
    subprocStdinBytes = [[filterParameters objectForKey:OFFilterProcessInputDataKey] retain];
    
    /* Parameters we don't store in an instance variable */
    NSString *workingDirectoryPath = [filterParameters objectForKey:OFFilterProcessWorkingDirectoryPathKey];
    NSDictionary *replacementEnvironment = [filterParameters objectForKey:OFFilterProcessReplacementEnvironmentKey];
    NSDictionary *additionalEnvironment = [filterParameters objectForKey:OFFilterProcessAdditionalEnvironmentKey];
    NSString *ensurePathDirectory = [filterParameters objectForKey:OFFilterProcessAdditionalPathEntryKey];
    BOOL detachFromTTY = [filterParameters boolForKey:OFFilterProcessDetachTTYKey defaultValue:YES];
    BOOL newProcessGroup = [filterParameters boolForKey:OFFilterProcessNewProcessGroupKey defaultValue:NO];
    
    /* Initialize ivars */
    /* In particular, make sure that all our fds are -1 instead of 0, so that if we dealloc early we don't end up closing stdin by accident */
    subprocStdinFd = -1;
    clear_copyout(&stdoutCopyBuf);
    clear_copyout(&stderrCopyBuf);
    child = -1;
    error = nil;
    bzero(&child_rusage, sizeof(child_rusage));
    state = OFFilterProcess_Initial;
    subprocStdinBytesWritten = 0;
    kevent_fd = -1;
    kevent_cf = NULL;
    
    if ([NSString isEmptyString:commandPath] || !arguments)
        OBRejectInvalidCall(self, _cmd, @"command path or arguments are missing");
    
    NSError *errorBuf = nil;
    
    /* Create the pipes */
    
    struct OFPipe input = {-1, -1}, output = {-1, -1}, errors = {-1, -1};
    if (subprocStdinBytes && [subprocStdinBytes length]) {
        if (!OFPipeCreate(&input, &errorBuf))
            goto fail_early;
        fcntl(input.write, F_SETFD, 1);  // Set close-on-exec
    }
    
    if (stdoutStream != nil && ![stdoutStream isNull]) {
        if (!OFPipeCreate(&output, &errorBuf))
            goto fail_early;
        fcntl(output.read, F_SETFD, 1);  // Set close-on-exec
    }
    
    if (stderrStream != stdoutStream && stderrStream != nil && ![stderrStream isNull]) {
        if (!OFPipeCreate(&errors, &errorBuf))
            goto fail_early;
        fcntl(errors.read, F_SETFD, 1);  // Set close-on-exec
    }
    
    if (0) {
    fail_early:
        OBASSERT(errorBuf != nil);
        [self _setError:errorBuf];
        state = OFFilterProcess_Finished;
        OFPipeClose(&input);
        OFPipeClose(&output);
        OFPipeClose(&errors);
        
        return self;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    /* Since we're vforking, build all our string buffers in the parent process (not sure if this is strictly necessary) */
    const char *toolPath = [fileManager fileSystemRepresentationWithPath:commandPath];
    if (access(toolPath, X_OK) != 0) {
        OBErrorWithErrno(&errorBuf, errno, toolPath, nil, nil);
        goto fail_early;
    }
    const char *chdirPath = workingDirectoryPath? [fileManager fileSystemRepresentationWithPath:workingDirectoryPath] : NULL;
    NSUInteger argumentIndex, argumentCount = [arguments count];
    const char **toolParameters = malloc(sizeof(const char *) * (argumentCount + 2));
    toolParameters[0] = toolPath;
    for (argumentIndex = 0; argumentIndex < argumentCount; argumentIndex++) {
        toolParameters[argumentIndex + 1] = [[arguments objectAtIndex:argumentIndex] cStringUsingEncoding:NSUTF8StringEncoding];
    }
    toolParameters[argumentIndex + 1] = NULL;
    
    char **toolEnvironment = computeToolEnvironment(replacementEnvironment, additionalEnvironment, ensurePathDirectory);
    
    /* Fork off a child process */
    
    child = fork();
    switch (child) {
        case -1: // Error
            ;
            NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Could not fork '%@'", @"OmniFoundation", OMNI_BUNDLE, @"error description"), commandPath];
            OBErrorWithErrno(&errorBuf, OMNI_ERRNO(), "fork()", nil, description);
            free(toolParameters);
            freeToolEnvironment(toolEnvironment);
            goto fail_early;
            
        case 0: { // Child
            
            // Close our parent's ends of the pipes. (Don't set them to -1, since we still share memory with it.)
            if (input.write != -1) close(input.write);
            if (output.read != -1) close(output.read);
            if (errors.read != -1) close(errors.read);

            if (detachFromTTY) {
                // Detach from the controlling tty so tools like hdiutil won't try to prompt us for input there (as opposed to stdin).
                int tty = open("/dev/tty", O_RDWR);
                if (tty >= 0) {
                    ioctl(tty, TIOCNOTTY, 0);
                    close(tty);
                }
            }
            if (newProcessGroup) {
                // Put the new process in its own process group.
                // This also detaches from the controlling TTY (but detaching from the controlling TTY doesn't necessarily mean a new pgrp).
                setpgrp();
            }
            
            // Purge our output buffers, in case we want to die with an error message
            fpurge(stderr);
            
            // Open /dev/null if requested; share fd between stderr and stdout if requested
            if (input.read == -1)
                input.read = open("/dev/null", O_RDONLY);
            if (output.write == -1 && stdoutStream != nil && [stdoutStream isNull])
                output.write = open("/dev/null", O_WRONLY);
            if (errors.write == -1 && output.write != -1 && stderrStream != nil && stderrStream == stdoutStream)
                errors.write = output.write;
            if (errors.write == -1 && stderrStream != nil && [stderrStream isNull])
                errors.write = open("/dev/null", O_WRONLY);
            
            // dup2 the supplied descriptors onto our standard in/out/error
            if (input.read != -1) {
                if (dup2(input.read, STDIN_FILENO) != STDIN_FILENO) {
                    perror("dup2(stdin)");
                    _exit(1); // Use _exit() not exit(): don't flush the parent's file buffers
                }
            }
            if (output.write != -1 && dup2(output.write, STDOUT_FILENO) != STDOUT_FILENO) {
                perror("dup2(stdout)");
                _exit(1); // Use _exit() not exit(): don't flush the parent's file buffers
            }
            if (errors.write != -1 && dup2(errors.write, STDERR_FILENO) != STDERR_FILENO) {
                perror("dup2(stderr)");
                _exit(1); // Use _exit() not exit(): don't flush the parent's file buffers
            }
            
            // Close the spare copies of the file descriptors that we've dup2'd onto our standard descriptors.
            if (input.read != -1) close(input.read);
            if (output.write != -1) close(output.write);
            if (errors.write != -1) close(errors.write);
            
            if (chdirPath != NULL) {
                if (chdir(chdirPath) != 0) {
                    write(STDERR_FILENO, "chdir: ", 7);
                    perror(chdirPath);
                    _exit(1);
                }
            }
            
            if (toolEnvironment)
                execve(toolPath, (char * const *)toolParameters, (char * const *)toolEnvironment);
            else
                execv(toolPath, (char * const *)toolParameters);
            perror(toolPath);
            _exit(1); // Use _exit() not exit(): don't flush the parent's file buffers
            OBASSERT_NOT_REACHED("_exit() should not return");
        }
        
        default: // Parent
            // Close the child's halves of the input and output pipes
            OFPipeCloseRead(&input);
            OFPipeCloseWrite(&output);
            OFPipeCloseWrite(&errors);
            free(toolParameters);
            freeToolEnvironment(toolEnvironment);
            break;
    }
    
    state = OFFilterProcess_Started;
    subprocStdinFd = input.write;
    init_copyout(&stdoutCopyBuf, output.read, stdoutStream);
    init_copyout(&stderrCopyBuf, errors.read, stderrStream);
    
    /* Set up the kevent filters */
    
    kevent_fd = kqueue();
    num_pending_changes = 0;
    
    if (subprocStdinFd != -1)
        EV_SET(&(pending_changes[num_pending_changes++]), subprocStdinFd, EVFILT_WRITE, EV_ADD|EV_ENABLE, 0, 0, NULL);
    if (stdoutCopyBuf.fd != -1) {
        EV_SET(&(pending_changes[num_pending_changes++]), stdoutCopyBuf.fd, EVFILT_READ, EV_ADD|EV_ENABLE, 0, 0, NULL);
        stdoutCopyBuf.filterEnabled = YES;
    }
    if (stderrCopyBuf.fd != -1) {
        EV_SET(&(pending_changes[num_pending_changes++]), stderrCopyBuf.fd, EVFILT_READ, EV_ADD|EV_ENABLE, 0, 0, NULL);
        stderrCopyBuf.filterEnabled = YES;
    }
    
    EV_SET(&(pending_changes[num_pending_changes++]), child, EVFILT_PROC, EV_ADD|EV_ENABLE, NOTE_EXIT, 0, NULL);
    
    // Don't block when writing to our child's input or output streams
    if (subprocStdinFd != -1) {
        if (fcntl(subprocStdinFd, F_SETFL, O_NONBLOCK))
            perror("fcntl(O_NONBLOCK)");
    }
#if 0
    if (subprocStdoutFd != -1)
        fcntl(subprocStdoutFd, F_SETFL, O_NONBLOCK);
    if (subprocStderrFd != -1)
        fcntl(subprocStderrFd, F_SETFL, O_NONBLOCK);
#endif
    
    return self;
}

- (void)dealloc
{
    if (kevent_cfrunloop != NULL) {
        CFRunLoopSourceInvalidate(kevent_cfrunloop);
        CFRelease(kevent_cfrunloop);
        kevent_cfrunloop = NULL;
    }
    
    if (poll_timer != NULL) {
        CFRunLoopTimerInvalidate(poll_timer);
        CFRelease(poll_timer);
        poll_timer = NULL;
    }
    
    if (kevent_cf != NULL) {
        CFFileDescriptorInvalidate(kevent_cf);
        CFRelease(kevent_cf);
        kevent_cf = NULL;
    }
    
    if (kevent_fd != -1) {
        close(kevent_fd);
        kevent_fd = -1;
    }
    
    if (child != -1) {
        kill(child, SIGTERM);
        child = -1;
    }
    
    free_copyout(&stdoutCopyBuf);
    free_copyout(&stderrCopyBuf);
    if (subprocStdinFd >= 0)
        close(subprocStdinFd);
    [subprocStdinBytes release];
    [commandPath release];
    [arguments release];
    [error autorelease];
    
    [super dealloc];
}

- (void)run
{
    // To avoid any errors due to race condition between getting an event that indicates we can write and actually doing it (during which time the child could die or close file descriptors), turn off SIGPIPE while talking to the child.
    sig_t oldPipeHandler = signal(SIGPIPE, SIG_IGN);
    
    while(state == OFFilterProcess_Started) {
        [self _handleKevents:keventBlockUntilActivity];
    }
    
    // Restore the old signal handler before we leave
    signal(SIGPIPE, oldPipeHandler);
}

- (BOOL)isRunning
{
    return ( state == OFFilterProcess_Started );
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
{
    
    /* Create the CFFileDescriptor and its corresponding CFRunLoopSource */
    if (kevent_cf == NULL) {
        CFFileDescriptorContext ctxt = {
                    .version = 0,
                       .info = self,
                     .retain = NULL,
                    .release = NULL,
            .copyDescription = NULL
        };
        kevent_cf = CFFileDescriptorCreate(kCFAllocatorDefault, kevent_fd, FALSE, keventRunLoopCallback, &ctxt);
        CFFileDescriptorEnableCallBacks(kevent_cf, kCFFileDescriptorReadCallBack);

        OBASSERT(kevent_cfrunloop == NULL);
    }
    
    if (kevent_cfrunloop == NULL) {
        kevent_cfrunloop = CFFileDescriptorCreateRunLoopSource(kCFAllocatorDefault, kevent_cf, 0);
    }
    
    /* Add our kevent handle to the run loop */
    CFRunLoopRef cfLoop = [aRunLoop getCFRunLoop];
    CFRunLoopAddSource(cfLoop, kevent_cfrunloop, (CFStringRef)mode);
    
    /* Add our streams to the run loop as well */
    if (stdoutCopyBuf.nsstream) {
        /* TODO: We should set ourselves as the stream's delegate, so that we can respond to NSStreamEventHasSpaceAvailable, etc, and avoid spinning */
        /* NB: Despite what the documentation says, -[NSCFOutputStream delegate] ininitally returns nil */
        [stdoutCopyBuf.nsstream scheduleInRunLoop:aRunLoop forMode:mode];
    }
    if (stderrCopyBuf.nsstream) {
        /* TODO: We should set ourselves as the stream's delegate, so that we can respond to NSStreamEventHasSpaceAvailable, etc, and avoid spinning */
        /* NB: Despite what the documentation says, -[NSCFOutputStream delegate] ininitally returns nil */
        [stderrCopyBuf.nsstream scheduleInRunLoop:aRunLoop forMode:mode];
    }
    
    /* Make sure to push any pending kevent filter changes to the kernel before we wait for them */
    [self _handleKevents:keventJustPush];
    
    if (kCFCoreFoundationVersionNumber >= 539 && kCFCoreFoundationVersionNumber < 550) {
        // RADAR 6898524: our kevent file descriptor source might decide not to notify us when it's readable.
        if (poll_timer == NULL) {
            CFRunLoopTimerContext ctxt = {
                        .version = 0,
                           .info = self,
                         .retain = NULL,
                        .release = NULL,
                .copyDescription = NULL
            };
            poll_timer = CFRunLoopTimerCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent()+0.5, 0.75, 0, 0, pollTimerRunLoopCallback, &ctxt);
        }
        CFRunLoopAddTimer(cfLoop, poll_timer, (CFStringRef)mode);
    }
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
{
    CFRunLoopRef cfLoop = [aRunLoop getCFRunLoop];

    if (poll_timer) {
        CFRunLoopRemoveTimer(cfLoop, poll_timer, (CFStringRef)mode);
    }
    
    if (kevent_cfrunloop == NULL)
        return;
    
    CFRunLoopRemoveSource(cfLoop, kevent_cfrunloop, (CFStringRef)mode);

    if (stdoutCopyBuf.nsstream)
        [stdoutCopyBuf.nsstream removeFromRunLoop:aRunLoop forMode:mode];
    if (stderrCopyBuf.nsstream)
        [stderrCopyBuf.nsstream removeFromRunLoop:aRunLoop forMode:mode];
}

+ (BOOL)runWithParameters:(NSDictionary *)filterParameters inMode:(NSString *)runLoopMode standardOutput:(NSData **)stdoutStreamData standardError:(NSData **)stderrStreamData  error:(NSError **)errorPtr;
{
    NSOutputStream *stdoutStream, *stderrStream;
    
    if (stdoutStreamData == NULL)
        stdoutStream = nil;
    else {
        stdoutStream = [NSOutputStream outputStreamToMemory];
        [stdoutStream open];
    }
    
    if (stderrStreamData == NULL)
        stderrStream = nil;
    else if (stderrStreamData == stdoutStreamData)
        stderrStream = stdoutStream;
    else {
        stderrStream = [NSOutputStream outputStreamToMemory];
        [stderrStream open];
    }
    
    OFFilterProcess *proc = [[self alloc] initWithParameters:filterParameters standardOutput:stdoutStream standardError:stderrStream];
    
    if ([proc error]) {
        if (errorPtr)
            *errorPtr = [proc error];
        [proc release];
        return NO;
    }

    NSException *pendingException = nil;
    
    if (runLoopMode == nil) {
        @try {
            [proc run];
        } @catch (NSException *e) {
            pendingException = [e retain];
        };
    } else {
        NSRunLoop *loop = [NSRunLoop currentRunLoop];
        
        [proc scheduleInRunLoop:loop forMode:runLoopMode];
        
        @try {
            while ([proc isRunning]) {
                [loop acceptInputForMode:runLoopMode beforeDate:[NSDate distantFuture]];
            }
        } @catch (NSException *e) {
            pendingException = [e retain];
        };
        
        [proc removeFromRunLoop:loop forMode:runLoopMode];
    }
    
    if (stdoutStream != nil)
        [stdoutStream close];
    if (stderrStream != nil && stderrStream != stdoutStream)
        [stderrStream close];
    
    if (stdoutStreamData != NULL) {
        NSData *result = [stdoutStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
        if (result == nil) // RADAR 6160521
            result = [NSData data];
        *stdoutStreamData = result;
    }
    
    if (stderrStreamData != NULL && stderrStreamData != stdoutStreamData) {
        NSData *result = [stderrStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
        if (result == nil) // RADAR 6160521
            result = [NSData data];
        *stderrStreamData = result;
    }
    
    BOOL success;
    
    if ([proc error]) {
        if (errorPtr)
            *errorPtr = [proc error];
        success = NO;
    } else if (stdoutStream && [stdoutStream streamStatus] == NSStreamStatusError) {
        if (errorPtr)
            *errorPtr = [stdoutStream streamError];
        success = NO;
    } else if (stderrStream && [stderrStream streamStatus] == NSStreamStatusError) {
        if (errorPtr)
            *errorPtr = [stderrStream streamError];
        success = NO;
    } else {
        success = YES;
    }
    
    [proc release];
    
    if (pendingException)
        [pendingException raise];
    
    return success;
}

@end

@implementation NSData (OFFilterProcess)

- (NSData *)filterDataThroughCommandAtPath:(NSString *)commandPath withArguments:(NSArray *)arguments includeErrorsInOutput:(BOOL)includeErrorsInOutput errorStream:(NSOutputStream *)errStream error:(NSError **)outError;
{
    
    NSMutableDictionary *filterSettings = [[NSMutableDictionary alloc] init];
    
    [filterSettings setObject:commandPath forKey:OFFilterProcessCommandPathKey];
    [filterSettings setObject:arguments forKey:OFFilterProcessArgumentsKey];
    [filterSettings setObject:self forKey:OFFilterProcessInputDataKey];
    
    NSOutputStream *resultStream = [NSOutputStream outputStreamToMemory];
    [resultStream open];
    
    OFFilterProcess *filter = [[OFFilterProcess alloc] initWithParameters:filterSettings
                                                           standardOutput:resultStream
                                                            standardError:(includeErrorsInOutput ? resultStream : errStream)];
    
    [filterSettings release];
    
    if ([filter error]) {
        if (outError) {
            *outError = [filter error];
            OBError(outError, OFFilterDataCommandReturnedErrorCodeError, ([NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Error filtering data through UNIX command: %@", @"OmniFoundation", OMNI_BUNDLE, @"Error encountered when trying to pass data through a UNIX command - parameter is underlying error text"), [*outError localizedDescription]]));
        }
        [filter release];
        return nil;
    }
    
    [filter run];
    
    if ([filter error]) {
        if (outError) {
            *outError = [filter error];
            OBError(outError, OFFilterDataCommandReturnedErrorCodeError, ([NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Error filtering data through UNIX command: %@", @"OmniFoundation", OMNI_BUNDLE, @"Error encountered when trying to pass data through a UNIX command - parameter is underlying error text"), [*outError localizedDescription]]));
        }
        [filter release];
        return nil;
    }
    
    [filter release];
    
    [resultStream close];
    
    if ([resultStream streamStatus] == NSStreamStatusError) {
        if (outError) {
            *outError = [resultStream streamError];
            OBError(outError, OFFilterDataCommandReturnedErrorCodeError, ([NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Error filtering data through UNIX command: %@", @"OmniFoundation", OMNI_BUNDLE, @"Error encountered when trying to pass data through a UNIX command - parameter is underlying error text"), [*outError localizedDescription]]));
        }
        return nil;
    }
    
    NSData *result = [resultStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
    if (result == nil) // RADAR 6160521
        result = [NSData data];
    return result;
}

- (NSData *)filterDataThroughCommandAtPath:(NSString *)commandPath withArguments:(NSArray *)arguments error:(NSError **)outError;
{
    return [self filterDataThroughCommandAtPath:commandPath withArguments:arguments includeErrorsInOutput:NO errorStream:nil error:outError];
}

- (NSData *)filterDataThroughCommandAtPath:(NSString *)commandPath withArguments:(NSArray *)arguments includeErrorsInOutput:(BOOL)includeErrorsInOutput error:(NSError **)outError;
{
    return [self filterDataThroughCommandAtPath:commandPath withArguments:arguments includeErrorsInOutput:includeErrorsInOutput errorStream:nil error:outError];
}

@end

@implementation OFFilterProcess (Private)

static void init_copyout(struct copy_out_state *into, int fd, NSOutputStream *stream)
{
    if (fd < 0) {
        clear_copyout(into);
        return;
    }
    OBASSERT(stream != nil);
    into->fd = fd;
    into->buffer = NULL;
    into->buffer_contents_start = 0;
    into->buffer_contents_length = 0;
    into->buffer_size = 0;
    into->filterEnabled = NO;
    into->nsstream = [stream retain];
    if ([stream streamStatus] == NSStreamStatusNotOpen)
        [stream open];
    into->streamReady = [stream hasSpaceAvailable];
}

static void clear_copyout(struct copy_out_state *into)
{
    into->buffer = NULL;
    into->buffer_contents_start = 0;
    into->buffer_contents_length = 0;
    into->buffer_size = 0;
    into->filterEnabled = NO;
    into->fd = -1;
    into->nsstream = nil;
    into->streamReady = NO;
}

static void free_copyout(struct copy_out_state *into)
{
    if (into->nsstream) {
        /* TODO: When we handle stream events, remember to un-set ourselves as the stream's delegate here */
        [into->nsstream release];
        into->nsstream = nil;
    }
    
    if (into->fd >= 0) {
        close(into->fd);
        into->fd = -1;
    }
    
    if (into->buffer != NULL) {
        free(into->buffer);
        into->buffer = NULL;
    }
}

- (void)_pushq:(int)ident filter:(short)evfilter flags:(unsigned short)flags
{
    if (!(num_pending_changes < OFFilterProcess_CHANGE_QUEUE_MAX))
        [self _handleKevents:keventJustPush];
    
    EV_SET(&(pending_changes[num_pending_changes++]), ident, evfilter, flags, 0, 0, 0);
}

/* The argument determines how/whether we process incoming events:
   timeoutType < 0:  don't even ask for events, just push any pending filter changes to the kernel
   timeoutType == 0: process any events, but don't block
   timeoutType > 0:  block indefinitely; return after processing something
 */
- (int)_handleKevents:(enum handleKeventsHow)timeoutType
{
#define KBUFSIZE 5
    struct kevent events[KBUFSIZE];
    int nevents;
    /* RADAR #6618025 / #6460269: on some architectures, kevent() tries to write to its (const *) timeout parameter */
    /* static const */ struct timespec zeroTimeout = { 0, 0 };
    
    if (stdoutCopyBuf.nsstream)
        copy_to_stream(&stdoutCopyBuf, self);
    if (stderrCopyBuf.nsstream)
        copy_to_stream(&stderrCopyBuf, self);
    
#if 0
    for(int i = 0; i < num_pending_changes; i++)
        NSLog(@"+[%d/%d] %@", i, num_pending_changes, OFDescribeKevent(&(pending_changes[i])));
#endif
    
    if (timeoutType < 0) {
        /* Just send changes, don't ask for any events */
        if (num_pending_changes) {
            nevents = kevent(kevent_fd, pending_changes, num_pending_changes, NULL, 0, &zeroTimeout);
            num_pending_changes = 0;
        } else
            nevents = 0;
    } else {
        /* Send changes if we have them; get a bufferful of event notifications */
        nevents = kevent(kevent_fd, num_pending_changes? pending_changes : NULL, num_pending_changes, events, KBUFSIZE, timeoutType == 0 ? &zeroTimeout : NULL);
        num_pending_changes = 0;
    }
    // printf("kevent -> %d\n", nevents);
    
    if (nevents < 0) {
        perror("kevent");
    }
    if (nevents > 0) {
        for(int event_index = 0; event_index < nevents; event_index ++) {
            struct kevent *ev = &(events[event_index]);
            BOOL deleteThis = NO;
            // NSLog(@"%@ got %@", OBShortObjectDescription(self), OFDescribeKevent(ev));
            
            if (ev->filter == EVFILT_PROC) {
                [self _waitpid];
                deleteThis = YES;
            } else if ((int)ev->ident == subprocStdinFd) {
                OBASSERT(ev->filter == EVFILT_WRITE);
                BOOL shutdown = NO;
                
                if (ev->flags & (EV_EOF|EV_ERROR)) {
                    // Child's input stream has become invalid somehow
                    // That's okay, as long as the child exits with success status
                    // printf("Subproc stdin error state, closing\n");
                    shutdown = YES;
                } else {
                    NSUInteger totalBytes = [subprocStdinBytes length];
                    if (totalBytes > subprocStdinBytesWritten) {
                        size_t toWrite = ( (totalBytes-subprocStdinBytesWritten) <= SIZE_MAX ) ? (totalBytes-subprocStdinBytesWritten) : SIZE_MAX;
                        ssize_t bytesWritten = write(subprocStdinFd, [subprocStdinBytes bytes] + subprocStdinBytesWritten, toWrite);
                        if (bytesWritten > 0) {
                            subprocStdinBytesWritten += bytesWritten;
                            // printf("Wrote %d bytes (%d left)\n", (int)bytesWritten, (int)(totalBytes-subprocStdinBytesWritten));
                        } else if (bytesWritten == -1) {
                            int local_errno = errno;
                            if (local_errno != EINTR && local_errno != EAGAIN) {
                                perror("OFFilterProcess");
                                shutdown = YES;
                            }
                        }
                    }
                    
                    if (subprocStdinBytesWritten >= totalBytes) {
                        // We're done, close the child's input stream
                        shutdown = YES;
                    }
                }
                
                
                if (shutdown) {
                    close(subprocStdinFd);
                    subprocStdinFd = -1;
                    /* Don't need to set deleteThis because EVFILT_READ/WRITE are automatically removed when their fd is closed */
                }
            } else if ((int)ev->ident == stdoutCopyBuf.fd) {
                copy_from_subprocess(ev, &stdoutCopyBuf, self);
            } else if ((int)ev->ident == stderrCopyBuf.fd) {
                copy_from_subprocess(ev, &stderrCopyBuf, self);
            } else {
                NSLog(@"%@: unexpected kevent %@", OBShortObjectDescription(self), OFDescribeKevent(ev));
                deleteThis = YES;
            }
            
            if (deleteThis) {
                /* Don't delete one-shot events, and don't delete error responses */
                if (!(ev->flags & EV_ONESHOT) && !(ev->flags & EV_ERROR)) {
                    [self _pushq:ev->ident filter:ev->filter flags:EV_DELETE];
                }
            }
        }
    }
    
    // printf("<%p> stdoutCopyBuf.fd == %d && stderrCopyBuf.fd == %d && child == %d\n", self, stdoutCopyBuf.fd, stderrCopyBuf.fd, child);
    if (stdoutCopyBuf.fd == -1 && stderrCopyBuf.fd == -1 && child < 0) {
        [self willChangeValueForKey:@"isRunning"];
        state = OFFilterProcess_Finished;
        [self didChangeValueForKey:@"isRunning"];
    }
    
    return (nevents >= 0)? nevents : 0;
}

static void copy_from_subprocess(const struct kevent *ev, struct copy_out_state *into, OFFilterProcess *self)
{
    OBASSERT(ev->filter == EVFILT_READ);
    
    if (into->buffer_contents_length == 0) {
        into->buffer_contents_length = 0;
        into->buffer_contents_start = 0;
    }

    if (!into->buffer) {
        into->buffer_size = BIG_PIPE_SIZE;
        if (into->buffer_size < (size_t)ev->data)
            into->buffer_size = (size_t)ev->data;
        into->buffer = malloc(into->buffer_size);
        into->buffer_contents_start = 0;
        into->buffer_contents_length = 0;
    }
    
    size_t buffer_used = into->buffer_contents_start + into->buffer_contents_length;
    ssize_t bytesRead = read(into->fd, into->buffer + buffer_used, into->buffer_size - buffer_used);
    // printf("Read %d bytes from fd %d for stream %p\n", (int)bytesRead, into->fd, into->nsstream);
    
    if (bytesRead == 0) {
        // We're done, close the child's output stream
        close(into->fd);
        into->fd = -1;
        // We don't close our output streams; caller can do that, or not, as it wants
    } else if (bytesRead > 0) {
        into->buffer_contents_length += bytesRead;
        copy_to_stream(into, self);
    } else {
        int local_errno = errno;
        if (local_errno == EINTR || local_errno == EAGAIN) {
            // Don't need to do anything here; we can just go around the loop again
        } else {
            // this is an actual error
            NSError *errorBuf = nil;
            OBErrorWithErrno(&errorBuf, local_errno, "read", nil, @"Error reading from subprocess");
            [self _setError:errorBuf];
            close(into->fd);
            into->fd = -1;
        }
    }
}

static void copy_to_stream(struct copy_out_state *into, OFFilterProcess *self)
{
    while (into->buffer_contents_length > 0 && into->streamReady) {
        NSInteger amountWritten = [into->nsstream write:(const uint8_t *)(into->buffer + into->buffer_contents_start) maxLength:into->buffer_contents_length];
        if (amountWritten > 0) {
            into->buffer_contents_length -= amountWritten;
            into->buffer_contents_start += amountWritten;
        } else if (amountWritten < 0) {
            // Whoa!
            [self _setError:[into->nsstream streamError]];
            into->streamReady = NO;
            break;
        }
        into->streamReady = [into->nsstream hasSpaceAvailable];
    }
    
    if (into->buffer_contents_length <= 0) {
        into->buffer_contents_length = 0;
        into->buffer_contents_start = 0;
    }
    
    if (into->streamReady && !into->filterEnabled) {
        [self _pushq:into->fd filter:EVFILT_READ flags:EV_ENABLE];
        into->filterEnabled = YES;
    }
    if (!into->streamReady && into->filterEnabled) {
        [self _pushq:into->fd filter:EVFILT_READ flags:EV_DISABLE];
        into->filterEnabled = NO;
    }
}

- (void)_setError:(NSError *)err
{
    [self willChangeValueForKey:@"error"];
    [err retain];
    [error release];
    error = err;
    // NSLog(@"%@ error <-- %@", OBShortObjectDescription(self), [error description]);
    [self didChangeValueForKey:@"error"];
}

- (BOOL)_waitpid
{
    pid_t waited;
    int childStatus;
    
    do {
        bzero(&child_rusage, sizeof(child_rusage));
        waited = wait4(child, &childStatus, 0, &child_rusage);
    } while (waited < 0 && (OMNI_ERRNO() == EINTR || OMNI_ERRNO() == EAGAIN));
    
    OBASSERT(waited == child);
    child = -1;
    
    if (WIFEXITED(childStatus)) {
        unsigned int terminationStatus = WEXITSTATUS(childStatus);
        if (terminationStatus != 0) {
            NSError *errBuf = [self error];
            OBErrorWithInfo(&errBuf, OFFilterDataCommandReturnedErrorCodeError, OFProcessExitStatusErrorKey, [NSNumber numberWithUnsignedInt:terminationStatus],  NSLocalizedDescriptionKey, [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"command '%@' returned %d", @"OmniFoundation", OMNI_BUNDLE, @"error description - a UNIX subprocess exited with a nonzero status"), commandPath, terminationStatus], nil);
            [self _setError:errBuf];
            return NO;
        } else {
            return YES;
        }
    } else {
        unsigned int terminationSignal = WTERMSIG(childStatus);
        NSError *errBuf = [self error];
        OBErrorWithInfo(&errBuf, OFFilterDataCommandReturnedErrorCodeError, OFProcessExitSignalErrorKey, [NSNumber numberWithUnsignedInt:terminationSignal], NSLocalizedDescriptionKey, [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"command '%@' exited due to signal %d (%s)", @"OmniFoundation", OMNI_BUNDLE, @"error description - a UNIX subprocess exited due to a signal"), commandPath, terminationSignal, strsignal(terminationSignal)], nil);
        [self _setError:errBuf];
        return NO;
    }
}    

static void keventRunLoopCallback(CFFileDescriptorRef f, CFOptionFlags callBackTypes, void *info)
{
    OFFilterProcess *self = info;
    
    OBASSERT(CFFileDescriptorGetNativeDescriptor(f) == self->kevent_fd);
    
    [self _handleKevents:keventProcessButDontBlock];
    
    // stupid 1-shot callbacks
    if (self->kevent_fd != -1)
        CFFileDescriptorEnableCallBacks(f, kCFFileDescriptorReadCallBack);
}

static void pollTimerRunLoopCallback(CFRunLoopTimerRef timer, void *info)
{
    OFFilterProcess *self = info;
    int handled;
    static BOOL haveNotedBugWorkaround = NO;
    
    OBASSERT(timer == self->poll_timer);
    
    handled = [self _handleKevents:keventProcessButDontBlock];
    
    if (handled && !haveNotedBugWorkaround) {
        haveNotedBugWorkaround = YES;
        NSLog(@"Using timer workaround for RADAR 6898524");
    }
}

@end

NSString *OFDescribeKevent(const struct kevent *ev)
{
    switch(ev->filter) {
        case EVFILT_PROC:
            ;
            NSString *s = [NSString stringWithFormat:@"filter=PROC pid=%d flags=%04x %04x", ev->ident, ev->flags, ev->fflags];
            if (ev->data)
                s = [s stringByAppendingFormat:@" data=%ld", (long)(ev->data)];
            return s;
        case EVFILT_READ:
            return [NSString stringWithFormat:@"filter=READ fd=%d flags=%04x %04x data=%ld", ev->ident, ev->flags, ev->fflags, (long)(ev->data)];
        case EVFILT_WRITE:
            return [NSString stringWithFormat:@"filter=WRITE fd=%d flags=%04x %04x data=%ld", ev->ident, ev->flags, ev->fflags, (long)(ev->data)];
        default:
            return [NSString stringWithFormat:@"filter=%d ident=%d flags=%04x %04x data=%ld", ev->filter, ev->ident, ev->flags, ev->fflags, (long)(ev->data)];
    }
}

#pragma mark Environment and path utilities

static char *pathStringIncludingDirectory(const char *currentPath, const char *pathdir, const char *sep)
{
    /* Make a copy so we can walk over it with strsep() */
    const size_t currentPathLen = strlen(currentPath);
    char *buf = malloc(currentPathLen + strlen(pathdir) + 2);
    strcpy(buf, currentPath);
    char *cursor, *ent;
    cursor = buf;
    while((ent = strsep(&cursor, sep)) != NULL) {
        if (strcmp(ent, pathdir) == 0) {
            /* The supplied path is already in $PATH; do nothing */
            free(buf);
            return NULL;
        }
    }
    
    /* Re-use the buffer to cons up the new value for $PATH */
    memcpy(buf, currentPath, currentPathLen);
    buf[currentPathLen] = *sep;
    strcpy(buf + currentPathLen + 1, pathdir);
    
    return buf;
}

#if 0
/* Not actually used right now, but might be handy in future */
BOOL OFIncludeInPathEnvironment(const char *pathdir)
{
    if (!pathdir || !*pathdir)
        return NO;
    
    /* Get the current path; if it's empty (?!!) just set it to the provided path and return */
    const char *currentPath = getenv("PATH");
    if (!currentPath || !*currentPath) {
        setenv("PATH", pathdir, 1);
        return YES;
    }
    
    char *newPath = pathStringIncludingDirectory(currentPath, pathdir, ":");
    if (newPath) {
        /* Set the new value */
        setenv("PATH", newPath, 1);
        free(newPath);
        return YES;
    } else {
        /* No change */
        return NO;
    }
}
#endif

static char *makeEnvEntry(id key, size_t *sepindex, id value)
{
    if (![value isKindOfClass:[NSData class]]) {
        if (![value isKindOfClass:[NSString class]]) {
            [NSException raise:NSInvalidArgumentException format:@"Invalid environment entry value of class %@", NSStringFromClass(value)];
            return NULL; /* NOTREACHED */
        }
        
        value = [value dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    }
    
    if (![key isKindOfClass:[NSData class]]) {
        if (![key isKindOfClass:[NSString class]]) {
            [NSException raise:NSInvalidArgumentException format:@"Invalid environment entry key of class %@", NSStringFromClass(key)];
            return NULL; /* NOTREACHED */
        }
        
        key = [key dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    }
    
    size_t keyLen = [key length];
    size_t valueLen = [value length];
    
    char *buf = malloc(keyLen + valueLen + 2);
    memcpy(buf, [key bytes], keyLen);
    buf[ keyLen ] = '=';
    memcpy(buf + keyLen + 1, [value bytes], valueLen);
    buf[ keyLen + 1 + valueLen ] = (char)0;
    
    if (sepindex)
        *sepindex = keyLen;
    
    return buf;
}

static char **computeToolEnvironment(NSDictionary *envp, NSDictionary *setenv, NSString *ensurePath)
{
    char **newEnviron;
    unsigned newEnvironSize, newEnvironCount;
    BOOL modified;
    
    
    /* If the caller supplied a replacement environment dictionary, convert it into the form used by execve() etc. Otherwise, get our own process environment and make a copy so we can modify it. */
    if (envp) {
        newEnvironSize = 1 + [envp count]; /* Add one in case we need to add $PATH */
        newEnviron = malloc(sizeof(*newEnviron) * (1 + newEnvironSize)); /* Add one for trailing NULL */
        newEnvironCount = 0;
        
        NSEnumerator *e = [envp keyEnumerator];
        id key;
        while( (key = [e nextObject]) != nil) {
            newEnviron[newEnvironCount++] = makeEnvEntry(key, NULL, [envp objectForKey:key]);
        }
        
        modified = YES;
    } else {
        if (!setenv && !ensurePath)
            return NULL;  /* We're not making any changes at all, just allow the child to inherit our environment */
        
        char ** oldEnviron = *_NSGetEnviron();
        for(newEnvironCount = 0; oldEnviron[newEnvironCount] != NULL; newEnvironCount ++)
            ;
        
        newEnvironSize = newEnvironCount + [setenv count] + 1;
        newEnviron = malloc(sizeof(*newEnviron) * (1 + newEnvironSize)); /* Add one for trailing NULL */
        
        for(unsigned envIndex = 0; oldEnviron[envIndex] != NULL; envIndex ++) {
            newEnviron[envIndex] = strdup(oldEnviron[envIndex]);
        }
        
        modified = NO;
    }
    
    if (setenv && [setenv count]) {
        NSEnumerator *e = [setenv keyEnumerator];
        id key;
        while( (key = [e nextObject]) != nil) {
            size_t namelen = 0;
            char *entry = makeEnvEntry(key, &namelen, [setenv objectForKey:key]);
            
            for(unsigned envIndex = 0; envIndex < newEnvironCount; envIndex ++) {
                if (strncmp(newEnviron[envIndex], entry, namelen) == 0) {
                    free(newEnviron[envIndex]);
                    newEnviron[envIndex] = entry;
                    entry = NULL;
                    break;
                }
            }
            
            if (entry) {
                newEnviron[newEnvironCount ++] = entry;
            }
        }
        
        modified = YES;
    }
    
    if (ensurePath) {
        const char *newdir = [ensurePath fileSystemRepresentation];
        for(unsigned envIndex = 0; envIndex < newEnvironCount; envIndex ++) {
            if (strncmp(newEnviron[envIndex], "PATH=", 5) == 0) {
                char *newPathStr = pathStringIncludingDirectory(newEnviron[envIndex], newdir, ":");
                if (newPathStr) {
                    newEnviron[envIndex] = realloc(newEnviron[envIndex], 6 + strlen(newPathStr));
                    strcpy(5 + newEnviron[envIndex], newPathStr);
                    free(newPathStr);
                    modified = YES;
                }
                break;
            }
        }
    }
    
    newEnviron[newEnvironCount] = NULL;
    
    if (!modified) {
        /* Just inherit our environment if we didn't make any changes */
        freeToolEnvironment(newEnviron);
        return NULL;
    } else {
        return newEnviron;
    }
}

static void freeToolEnvironment(char **envp)
{
    if (!envp)
        return;
    for(char **envcursor = envp; *envcursor; envcursor ++)
        free(*envcursor);
    free(envp);
}


