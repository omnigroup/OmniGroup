// Copyright 1998-2005,2007,2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFExtensions.h>

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/NSStream.h>

#import <OmniFoundation/CFData-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <OmniFoundation/NSMutableData-OFExtensions.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/OFDataBuffer.h>
#import <OmniFoundation/OFRandom.h>

#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniBase/NSError-OBExtensions.h>
#import <poll.h>

RCS_ID("$Id$")

@implementation NSData (OFExtensions)

+ (NSData *)randomDataOfLength:(NSUInteger)byteCount;
{
    OFByte *bytes = (OFByte *)malloc(byteCount);
    
    for (NSUInteger byteIndex = 0; byteIndex < byteCount; byteIndex++)
        bytes[byteIndex] = OFRandomNext() & 0xff;

    // Send to self rather than NSData so that we'll get mutable instances when the caller sent the message to NSMutableData
    // clang checker-0.209 incorrectly reports this as a +1 ref <http://llvm.org/bugs/show_bug.cgi?id=4292>
    return objc_msgSend(self, @selector(dataWithBytesNoCopy:length:), bytes, byteCount);
}

+ dataWithDecodedURLString:(NSString *)urlString
{
    if (urlString == nil)
        return [NSData data];
    else
        return [urlString dataUsingCFEncoding:[NSString urlEncoding] allowLossyConversion:NO hexEscapes:@"%"];
}

static inline unichar hex(int i)
{
    static const char hexDigits[16] = {
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'
    };

    return (unichar)hexDigits[i];
}

- (NSUInteger)lengthOfQuotedPrintableStringWithMapping:(const OFQuotedPrintableMapping *)qpMap
{
    unsigned const char *sourceBuffer;
    NSUInteger sourceLength, sourceIndex, quotedPairs;

    sourceLength = [self length];
    if (sourceLength == 0)
        return 0;
    sourceBuffer = [self bytes];

    quotedPairs = 0;

    for (sourceIndex = 0; sourceIndex < sourceLength; sourceIndex++) {
        unsigned char ch = sourceBuffer[sourceIndex];
        if (qpMap->map[ch] == 1)
            quotedPairs ++;
    }

    return sourceLength + ( 2 * quotedPairs );
}

- (NSString *)quotedPrintableStringWithMapping:(const OFQuotedPrintableMapping *)qpMap lengthHint:(unsigned)outputLengthHint
{
    unsigned const char *sourceBuffer;
    int sourceLength;
    int sourceIndex;
    unichar *destinationBuffer;
    int destinationBufferSize;
    int destinationIndex;
    NSString *escapedString;

    sourceLength = [self length];
    if (sourceLength == 0)
        return [NSString string];
    sourceBuffer = [self bytes];

    if (outputLengthHint > 0)
        destinationBufferSize = outputLengthHint;
    else
        destinationBufferSize = sourceLength + (sourceLength >> 2) + 12;
    destinationBuffer = malloc((destinationBufferSize) * sizeof(*destinationBuffer));
    destinationIndex = 0;

    for (sourceIndex = 0; sourceIndex < sourceLength; sourceIndex++) {
        unsigned char ch;
        unsigned char chtype;

        ch = sourceBuffer[sourceIndex];

        if (destinationIndex >= destinationBufferSize - 3) {
            destinationBufferSize += destinationBufferSize >> 2;
            destinationBuffer = realloc(destinationBuffer, (destinationBufferSize) * sizeof(*destinationBuffer));
        }

        chtype = qpMap->map[ ch ];
        if (!chtype) {
            destinationBuffer[destinationIndex++] = ch;
        } else {
            destinationBuffer[destinationIndex++] = qpMap->translations[chtype-1];
            if (chtype == 1) {
                // "1" indicates a quoted-printable rather than a translation
                destinationBuffer[destinationIndex++] = hex((ch & 0xF0) >> 4);
                destinationBuffer[destinationIndex++] = hex(ch & 0x0F);
            }
        }
    }

    escapedString = [[[NSString alloc] initWithCharactersNoCopy:destinationBuffer length:destinationIndex freeWhenDone:YES] autorelease];

    return escapedString;
}

//
// Misc extensions
//

- (NSUInteger)indexOfFirstNonZeroByte;
{
    const OFByte *bytes, *bytePtr;
    NSUInteger byteIndex, byteCount;

    byteCount = [self length];
    bytes = (const unsigned char *)[self bytes];

    for (byteIndex = 0, bytePtr = bytes; byteIndex < byteCount; byteIndex++, bytePtr++) {
	if (*bytePtr != 0)
	    return byteIndex;
    }

    return NSNotFound;
}

- (NSData *)copySHA1Signature;
{
    return (NSData *)OFDataCreateSHA1Digest(kCFAllocatorDefault, (CFDataRef)self);
}

- (NSData *)sha1Signature;
{
    return [[self copySHA1Signature] autorelease];
}

- (NSData *)sha256Signature;
{
    return [(NSData *)OFDataCreateSHA256Digest(kCFAllocatorDefault, (CFDataRef)self) autorelease];
}

- (NSData *)md5Signature;
{
    return [(NSData *)OFDataCreateMD5Digest(kCFAllocatorDefault, (CFDataRef)self) autorelease];
}

- (NSData *)signatureWithAlgorithm:(NSString *)algName;
{
    switch ([algName caseInsensitiveCompare:@"sha1"]) {
        case NSOrderedSame:
            return [self sha1Signature];
        case NSOrderedAscending:
            switch ([algName caseInsensitiveCompare:@"md5"]) {
                case NSOrderedSame:
                    return [self md5Signature];
                default:
                    break;
            }
            break;
        case NSOrderedDescending:
            switch ([algName caseInsensitiveCompare:@"sha256"]) {
                case NSOrderedSame:
                    return [self sha256Signature];
                default:
                    break;
            }
            break;
        default:
            break;
    }
    
    return nil;
}

- (BOOL)hasPrefix:(NSData *)data;
{
    unsigned const char *selfPtr, *ptr, *end;

    if ([self length] < [data length])
        return NO;

    ptr = [data bytes];
    end = ptr + [data length];
    selfPtr = [self bytes];
    
    while(ptr < end) {
        if (*ptr++ != *selfPtr++)
            return NO;
    }
    return YES;
}

- (BOOL)containsData:(NSData *)data
{
    NSUInteger dataLocation = [self indexOfBytes:[data bytes] length:[data length]];
    return (dataLocation != NSNotFound);
}

- (NSRange)rangeOfData:(NSData *)data;
{
    NSUInteger patternLength, patternLocation;

    patternLength = [data length];
    patternLocation = [self indexOfBytes:[data bytes] length:patternLength];
    if (patternLocation == NSNotFound)
        return NSMakeRange(NSNotFound, 0);
    else
        return NSMakeRange(patternLocation, patternLength);
}

- (NSUInteger)indexOfBytes:(const void *)patternBytes length:(NSUInteger)patternLength;
{
    return [self indexOfBytes:patternBytes length:patternLength range:NSMakeRange(0, [self length])];
}

- (NSUInteger)indexOfBytes:(const void *)patternBytes length:(NSUInteger)patternLength range:(NSRange)searchRange
{
    unsigned const char *selfBufferStart, *selfPtr, *selfPtrEnd;
    NSUInteger selfLength;
    
    selfLength = [self length];
    if (searchRange.location > selfLength ||
        (searchRange.location + searchRange.length) > selfLength) {
        OBRejectInvalidCall(self, _cmd, @"Range {%u,%u} exceeds length %u", searchRange.location, searchRange.length, selfLength);
    }

    if (patternLength == 0)
        return searchRange.location;
    if (patternLength > searchRange.length) {
        // This test is a nice shortcut, but it's also necessary to avoid crashing: zero-length CFDatas will sometimes(?) return NULL for their bytes pointer, and the resulting pointer arithmetic can underflow.
        return NSNotFound;
    }
    
    
    selfBufferStart = [self bytes];
    selfPtr    = selfBufferStart + searchRange.location;
    selfPtrEnd = selfBufferStart + searchRange.location + searchRange.length + 1 - patternLength;
    
    for (;;) {
        if (memcmp(selfPtr, patternBytes, patternLength) == 0)
            return (selfPtr - selfBufferStart);
        
        selfPtr++;
        if (selfPtr == selfPtrEnd)
            break;
        selfPtr = memchr(selfPtr, *(const char *)patternBytes, (selfPtrEnd - selfPtr));
        if (!selfPtr)
            break;
    }
    return NSNotFound;
}

- propertyList
{
    CFPropertyListRef propList;
    CFStringRef errorString;
    NSException *exception;
    
    propList = CFPropertyListCreateFromXMLData(kCFAllocatorDefault, (CFDataRef)self, kCFPropertyListImmutable, &errorString);
    
    if (propList != NULL)
        return [(id <NSObject>)propList autorelease];
    
    exception = [[NSException alloc] initWithName:NSParseErrorException reason:(NSString *)errorString userInfo:nil];
    
    [(NSString *)errorString release];
    
    [exception autorelease];
    [exception raise];
    /* NOT REACHED */
    return nil;
}


- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically createDirectories:(BOOL)shouldCreateDirectories error:(NSError **)outError;
{
    if (shouldCreateDirectories && ![[NSFileManager defaultManager] createPathToFile:path attributes:nil error:outError])
        return NO;

    return [self writeToFile:path options:atomically ? NSAtomicWrite : 0 error:outError];
}

- (NSData *)dataByAppendingData:(NSData *)anotherData;
{
    unsigned int myLength, otherLength;
    NSMutableData *buffer;
    NSData *result;
    
    if (!anotherData)
        return [[self copy] autorelease];

    myLength = [self length];
    otherLength = [anotherData length];

    if (!otherLength) return [[self copy] autorelease];
    if (!myLength) return [[anotherData copy] autorelease];

    buffer = [[NSMutableData alloc] initWithCapacity:myLength + otherLength];
    [buffer appendData:self];
    [buffer appendData:anotherData];
    result = [buffer copy];
    [buffer release];

    return [result autorelease];
}

#if 0 // Supplanted by OFFilterProcess

// UNIX filters

struct _OFPipe {
    int read, write;
};
static BOOL _OFPipeCreate(struct _OFPipe *p, NSError **outError)
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

- (NSData *)filterDataThroughCommandAtPath:(NSString *)commandPath withArguments:(NSArray *)arguments includeErrorsInOutput:(BOOL)includeErrorsInOutput errorStream:(NSOutputStream *)errorStream error:(NSError **)outError;
{
    OBPRECONDITION(includeErrorsInOutput == NO || errorStream == nil); // Having both set makes no sense
    
    struct _OFPipe input, output, error;
    if (!_OFPipeCreate(&input, outError))
        return nil;
    if (!_OFPipeCreate(&output, outError)) {
        close(input.read);
        close(input.write);
        return nil;
    }
    if (!_OFPipeCreate(&error, outError)) {
        close(input.read);
        close(input.write);
        close(output.read);
        close(output.write);
        return nil;
    }
    
    // TODO: The command arguments are leaked due to strdup()
    const char *toolPath = [[NSFileManager defaultManager] fileSystemRepresentationWithPath:commandPath];
    unsigned int argumentIndex, argumentCount = [arguments count];
    char *toolParameters[argumentCount + 2];
    toolParameters[0] = strdup(toolPath);
    for (argumentIndex = 0; argumentIndex < argumentCount; argumentIndex++) {
        toolParameters[argumentIndex + 1] = strdup([[arguments objectAtIndex:argumentIndex] UTF8String]);
    }
    toolParameters[argumentCount + 1] = NULL;

    pid_t child = vfork();
    switch (child) {
        case -1: // Error
            close(input.read);
            close(input.write);
            close(output.read);
            close(output.write);
            close(error.read);
            close(error.write);
            NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Error filtering data through UNIX command %@", @"OmniFoundation", OMNI_BUNDLE, @"error description"), commandPath];
            OBErrorWithErrno(outError, OMNI_ERRNO(), "fork()", nil, description);
            return nil;

        case 0: { // Child

            // Detach from the controlling tty so tools like hdiutil won't try to prompt us for input there (as opposed to stdin).
            int tty = open("/dev/tty", O_RDWR);
            if (tty >= 0) {
                ioctl(tty, TIOCNOTTY, 0);
                close(tty);
            }
            
            // Close the parent's halves of the input and output pipes
            close(input.write);
            close(output.read);
            close(error.read);
            
            if (dup2(input.read, STDIN_FILENO) != STDIN_FILENO)
                _exit(1); // Use _exit() not exit(): don't flush the parent's file buffers
            if (dup2(output.write, STDOUT_FILENO) != STDOUT_FILENO)
                _exit(1); // Use _exit() not exit(): don't flush the parent's file buffers
            if (includeErrorsInOutput) {
                if (dup2(STDOUT_FILENO, STDERR_FILENO) != STDERR_FILENO)
                    _exit(1); // Use _exit() not exit(): don't flush the parent's file buffers
            } else if (errorStream) {
                if (dup2(error.write, STDERR_FILENO) != STDERR_FILENO)
                    _exit(1); // Use _exit() not exit(): don't flush the parent's file buffers
                close(error.write); // We've copied this to STDERR_FILENO, we can close the other descriptor now
            } else {
                // We don't care what the child puts on stderr, but closing this would yield a SIGPIPE in the child.
                // We could dup2 this onto /dev/null, but this way the errors will make their way into the console at least.
                //close(STDERR_FILENO);
            }

            close(input.read); // We've copied this to STDIN_FILENO, we can close the other descriptor now
            close(output.write); // We've copied this to STDOUT_FILENO, we can close the other descriptor now

            execv(toolPath, toolParameters);
            _exit(1); // Use _exit() not exit(): don't flush the parent's file buffers
            OBASSERT_NOT_REACHED("_exit() should not return");
        }
            
        default: // Parent
            break;
    }

    int childStatus;

    // Close the child's halves of the input and output pipes
    close(input.read);
    close(output.write);
    close(error.write);
    
    // Don't block when writing to our child's input or output streams
    fcntl(input.write, F_SETFL, O_NONBLOCK);
    fcntl(output.read, F_SETFL, O_NONBLOCK);
    fcntl(error.read, F_SETFL, O_NONBLOCK);

    unsigned int writeDataOffset = 0, writeDataLength = [self length];
    const void *writeBytes = [self bytes];
    const char *failCmd;

    unsigned int filteredDataOffset = 0, filteredDataCapacity = 8192;
    NSMutableData *filteredData = [NSMutableData dataWithLength:filteredDataCapacity];
    void *filteredDataBytes = [filteredData mutableBytes];
    
    // To avoid any errors due to race condition between getting a poll() result that indicates we can write and actually doing it (during which time the child could die or close file descriptors), turn off SIGPIPE while talking to the child.
    sig_t oldPipeHandler = signal(SIGPIPE, SIG_IGN);
    
    while (output.read >= 0 || error.read >= 0) {
        if (input.write >= 0 && writeDataOffset >= writeDataLength) {
            // We're done, close the child's input stream
            close(input.write);
            input.write = -1;
        }
        
        short inputWriteEvents, outputReadEvents, errorReadEvents;
        {
            struct pollfd pollThese[3];
            bzero(pollThese, sizeof(pollThese));
            nfds_t slotsFilled = 0;
            int inputWriteSlot = -1, outputReadSlot = -1, errorReadSlot = -1;
            
            if (input.write >= 0) {
                pollThese[inputWriteSlot = slotsFilled++] = (struct pollfd){
                    .fd = input.write,
                    .events = POLLOUT
                };
            }
            
            if (output.read >= 0) {
                pollThese[outputReadSlot = slotsFilled++] = (struct pollfd){
                    .fd = output.read,
                    .events = POLLIN
                };
            }
            
            if (error.read >= 0) {
                pollThese[errorReadSlot = slotsFilled++] = (struct pollfd){
                    .fd = error.read,
                    .events = POLLIN
                };
            }
            
            if (slotsFilled == 0)
                break;
            
            if (poll(pollThese, slotsFilled, -1) < 1) {
                if (OMNI_ERRNO() == EINTR || OMNI_ERRNO() == EAGAIN)
                    continue;
                else {
                    failCmd = "poll()";
                    goto ioFailure;
                }
            }
            
            inputWriteEvents = (inputWriteSlot >= 0) ? pollThese[inputWriteSlot].revents : 0;
            outputReadEvents = (outputReadSlot >= 0) ? pollThese[outputReadSlot].revents : 0;
            errorReadEvents = (errorReadSlot >= 0) ? pollThese[errorReadSlot].revents : 0;
        }
        
        // Write some data to the child's input stream
        if (inputWriteEvents & POLLOUT) {
            int bytesWritten = write(input.write, writeBytes + writeDataOffset, writeDataLength - writeDataOffset);
            if (bytesWritten > 0) {
                writeDataOffset += bytesWritten;
            } else if (bytesWritten == -1) {
                if (OMNI_ERRNO() == EINTR || OMNI_ERRNO() == EAGAIN)
                    continue;
                else {
                    failCmd = "write()";
                    goto ioFailure;
                }
            }
        } else if (inputWriteEvents & (POLLERR|POLLHUP|POLLNVAL)) {
            // Child's input stream has become invalid somehow
            // That's okay, as long as the child exits with success status
            close(input.write);
            input.write = -1;
        }

        // Read filtered data from the child's output stream
        if (outputReadEvents & POLLIN) {
            int bytesRead = read(output.read, filteredDataBytes + filteredDataOffset, filteredDataCapacity - filteredDataOffset);
            
            if (bytesRead == 0) {
                // We're done, close the child's output stream
                close(output.read);
                output.read = -1;
            } else if (bytesRead > 0) {
                filteredDataOffset += bytesRead;
                if (filteredDataOffset == filteredDataCapacity) {
                    filteredDataCapacity += filteredDataCapacity; // Double the capacity
                    [filteredData setLength:filteredDataCapacity];
                    filteredDataBytes = [filteredData mutableBytes];
                }
            } else {
                if (OMNI_ERRNO() == EINTR || OMNI_ERRNO() == EAGAIN)
                    continue;
                else {
                    failCmd = "read(stdout)";
                    goto ioFailure;
                }
            } 
        } else if (outputReadEvents & (POLLERR|POLLHUP|POLLNVAL)) {
            // Child's output stream has become invalid somehow
            // this generally shouldn't happen --- we should get a failure from read(), above, instead
            failCmd = "poll/read";
            goto ioFailure;
        }
        
        // Read errors
        if (errorReadEvents & POLLIN) {
            uint8_t buffer[1024];
            ssize_t bytesRead = read(error.read, buffer, sizeof(buffer));

            if (bytesRead == 0) {
                // End of errors
                close(error.read);
                error.read = -1;
            } else if (bytesRead > 0) {
                ssize_t byteCountLeftToAppend = bytesRead;
                uint8_t *bytesToAppend = buffer;
                while (byteCountLeftToAppend > 0) {
                    int streamBytesWritten = [errorStream write:bytesToAppend maxLength:byteCountLeftToAppend];
                    if (streamBytesWritten > 0) {
                        byteCountLeftToAppend -= streamBytesWritten;
                        bytesToAppend += streamBytesWritten;
                    } else {
                        if (outError)
                            *outError = [errorStream streamError];
                        failCmd = "-[NSStream write:maxLength:]";
                        goto ioFailure;
                    }
                }
            } else {
                if (OMNI_ERRNO() == EINTR || OMNI_ERRNO() == EAGAIN)
                    continue;
                else {
                    failCmd = "read(stderr)";
                    goto ioFailure;
                }
            } 
        }
    }
    
    // Restore the old signal handler before we leave
    signal(SIGPIPE, oldPipeHandler);

    if (0) {
        // Exit from the above loop when we get an unexpected error return.
ioFailure:
        close(input.write);
        close(output.read);
        close(error.read);
        waitpid(child, &childStatus, 0);
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Error filtering data through UNIX command %@", @"OmniFoundation", OMNI_BUNDLE, @"error description"), commandPath];
        OBErrorWithErrno(outError, OMNI_ERRNO(), failCmd, nil, description);
        return nil;
    }

    if (input.write >= 0) {
        // The child closed its output stream without reading all its input.  (This can happen, for example, when the child is "head".)
        close(input.write);
        input.write = -1;
    }
    
    OBASSERT(output.read < 0);
    [filteredData setLength:filteredDataOffset];
    
    OBASSERT(error.read < 0);
    // We don't call -close on the error stream, caller should probably do this, in case it wants to concatenate multiple things into a stream
    
    pid_t waited;
    do {
        waited = waitpid(child, &childStatus, 0);
    } while (waited < 0 && (OMNI_ERRNO() == EINTR || OMNI_ERRNO() == EAGAIN));

    if (WIFEXITED(childStatus)) {
        unsigned int terminationStatus = WEXITSTATUS(childStatus);
        if (terminationStatus != 0 && outError != NULL) {
            OBErrorWithInfo(outError, OFFilterDataCommandReturnedErrorCodeError, OBExceptionPosixErrorNumberKey, [NSNumber numberWithInt:OMNI_ERRNO()], NSLocalizedDescriptionKey, [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Error filtering data through UNIX command %@: command returned %d", @"OmniFoundation", OMNI_BUNDLE, @"error description"), commandPath, terminationStatus], nil);
            return nil;
        }
    } else {
        unsigned int terminationSignal = WTERMSIG(childStatus);
        OBErrorWithInfo(outError, OFFilterDataCommandReturnedErrorCodeError, OBExceptionPosixErrorNumberKey, [NSNumber numberWithInt:OMNI_ERRNO()], NSLocalizedDescriptionKey, [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Error filtering data through UNIX command %@: command exited due to signal %d", @"OmniFoundation", OMNI_BUNDLE, @"error description"), commandPath, terminationSignal], nil);
        return nil;
    }

    return [NSData dataWithData:filteredData];
}

- (NSData *)filterDataThroughCommandAtPath:(NSString *)commandPath withArguments:(NSArray *)arguments includeErrorsInOutput:(BOOL)includeErrorsInOutput;
{
    NSError *error = nil;
    NSData *filteredData = [self filterDataThroughCommandAtPath:commandPath withArguments:arguments includeErrorsInOutput:includeErrorsInOutput errorStream:nil error:&error];
    if (error != nil)
        [NSException raise:NSGenericException posixErrorNumber:[[[error userInfo] objectForKey:OBExceptionPosixErrorNumberKey] intValue] format:@"%@", [error localizedDescription]];

    return filteredData;
}

- (NSData *)filterDataThroughCommandAtPath:(NSString *)commandPath withArguments:(NSArray *)arguments;
{
    return [self filterDataThroughCommandAtPath:commandPath withArguments:arguments includeErrorsInOutput:NO];
}
#endif

@end

