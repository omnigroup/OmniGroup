// Copyright 2003-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONSocketStream.h>
#import <OmniNetworking/ONTCPSocket.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <XCTest/XCTest.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/types.h>
#include <sys/socket.h>

RCS_ID("$Id$");

@interface ONSocketStreamTests : XCTestCase
{
    pthread_t writer;
    NSData *writerBuf;
    int socket_fd;
    BOOL withDelays;
    int writerError;
}

@end

@implementation ONSocketStreamTests

static void *feedData(void *arg)
{
    NSUInteger bytesWritten, totalBytes;
    NSData *buf = ((ONSocketStreamTests *)arg)->writerBuf;
    int fd = ((ONSocketStreamTests *)arg)->socket_fd;
    BOOL delays = ((ONSocketStreamTests *)arg)->withDelays;

    totalBytes = [buf length];
    bytesWritten = 0;

    while (bytesWritten < totalBytes) {
        size_t bytesThisCall;

        if (delays)
            bytesThisCall = 1;
        else
            bytesThisCall = totalBytes - bytesWritten;

        ssize_t result = write(fd, [buf bytes] + bytesWritten, bytesThisCall);
        if (result < 1) {
            ((ONSocketStreamTests *)arg)->writerError = errno;
            return NULL;
        } else {
            bytesWritten += result;
        }

        if (delays) {
            usleep(500);
        }
    }

    close(fd);

    ((ONSocketStreamTests *)arg)->writerError = 0;
    return NULL;
}

- (ONSocket *)socketProducingData:(NSData *)buf withDelays:(BOOL)delays
{
    int fds[2];

    if (socketpair(PF_UNIX, SOCK_STREAM, 0, fds)) {
        [NSException raise:NSGenericException posixErrorNumber:errno format:@"Unable to create socket pair (%s)", strerror(errno)];
    }

    writerBuf = [buf retain];
    socket_fd = fds[0];
    withDelays = delays;

    if (pthread_create(&writer, NULL, feedData, (void *)self)) {
        [NSException raise:NSGenericException posixErrorNumber:errno format:@"Unable to create writer thread (%s)", strerror(errno)];
    }

    return [ONTCPSocket socketWithConnectedFileDescriptor:fds[1] shouldClose:YES];
}

- (void)joinWriter
{
    if (pthread_join(writer, NULL)) {
        [NSException raise:NSGenericException posixErrorNumber:errno format:@"Error waiting for writer thread (%s)", strerror(errno)];
    }

    if (writerError != 0) {
        [NSException raise:NSGenericException posixErrorNumber:writerError format:@"Writer thread encountered an error (%s)", strerror(writerError)];
    }

    [writerBuf release];
    writerBuf = nil;
    socket_fd = -1;
    writerError = 0;
}

- (NSArray *)parseData:(NSData *)buf forceBoundaries:(BOOL)delays peekFirst:(BOOL)shouldPeek
{
    ONSocket *readSocket;
    ONSocketStream *readStream;
    NSMutableArray *results;
    NSString *result, *peekedResult;

    readSocket = [self socketProducingData:buf withDelays:delays];
    readStream = [[ONSocketStream alloc] initWithSocket:readSocket];
    results = [[NSMutableArray alloc] init];
    [results autorelease];

    for(;;) {
        if (shouldPeek)
            peekedResult = [readStream readLineAndAdvance:NO];
        else
            peekedResult = nil;

        result = [readStream readLineAndAdvance:YES];
        
        if (shouldPeek)
            XCTAssertEqualObjects(result, peekedResult, @"Peeked line should be the same as subsequently read line");
        
        if (result == nil)
            break;

        [results addObject:result];
    } 

    [readStream release];
    [self joinWriter];

    return results;
}

- (void)testDataInAllPermutations:(NSData *)buf expectResults:(NSArray *)expectedResults;
{
    XCTAssertTrue([[self parseData:buf forceBoundaries:NO  peekFirst:NO ] isEqual:expectedResults]);
    XCTAssertTrue([[self parseData:buf forceBoundaries:NO  peekFirst:YES] isEqual:expectedResults]);
    XCTAssertTrue([[self parseData:buf forceBoundaries:YES peekFirst:NO ] isEqual:expectedResults]);
    XCTAssertTrue([[self parseData:buf forceBoundaries:YES peekFirst:YES] isEqual:expectedResults]);
}

- (void)testSimpleCase
{
    const char *simpleData = "Here at the frontier there are falling leaves.\n"
                             "Although all my neighbors are barbarians,\r\n"
                             "and you --- you are a thousand miles away,\r"
                             "still there are two cups on my table.\n";
    NSArray *simpleLines = [NSArray arrayWithObjects:
        @"Here at the frontier there are falling leaves.",
        @"Although all my neighbors are barbarians,",
        @"and you --- you are a thousand miles away,",
        @"still there are two cups on my table.",
        nil];

    [self testDataInAllPermutations:[NSData dataWithBytes:simpleData length:strlen(simpleData)]
                      expectResults:simpleLines];
}

- (void)testTrailingLine
{
    const char *untData = "This is some text\nwhose last line has no terminator";
    NSArray *untLines = [NSArray arrayWithObjects:
        @"This is some text", @"whose last line has no terminator",
        nil];

    [self testDataInAllPermutations:[NSData dataWithBytes:untData length:strlen(untData)]
                      expectResults:untLines];
}

- (void)testBlankLines
{
    const char *blankCRline = "Line 1\r\rLine 3\r";
    const char *blankLFline = "Line 1\n\nLine 3\n";
    const char *blankCRLFline = "Line 1\r\n\r\nLine 3\r\n";
    const char *blankLFCRline = "Line 1\n\r\n\rLine 3\n\r";
    const char *blankCRCRLFline = "Line 1\r\r\n\r\r\nLine 3\r\r\n";

    NSArray *lines = [NSArray arrayWithObjects: @"Line 1", @"", @"Line 3", nil];

    [self testDataInAllPermutations:[NSData dataWithBytes:blankCRline     length:strlen(blankCRline)    ] expectResults:lines];
    [self testDataInAllPermutations:[NSData dataWithBytes:blankLFline     length:strlen(blankLFline)    ] expectResults:lines];
    [self testDataInAllPermutations:[NSData dataWithBytes:blankCRLFline   length:strlen(blankCRLFline)  ] expectResults:lines];
    [self testDataInAllPermutations:[NSData dataWithBytes:blankLFCRline   length:strlen(blankLFCRline)  ] expectResults:lines];
    [self testDataInAllPermutations:[NSData dataWithBytes:blankCRCRLFline length:strlen(blankCRCRLFline)] expectResults:lines];
}

@end

