// Copyright 2003-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWDataStream.h>
#import <OWF/OWDataStreamCursor.h>

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <OmniBase/rcsid.h>
#import <OmniFoundation/NSData-OFExtensions.h>

RCS_ID("$Id$");

static NSData *someData;

@interface DataStreamTests : XCTestCase
{
    NSData *inputData;
    OWDataStream *dataStream;
    NSMutableArray *readerStates;
    NSConditionLock *runningProcs;
}


@end

@implementation DataStreamTests

// Create some data to run through the stream

+ (void)initialize
{
    [super initialize];
    if (someData == nil) {
        NSMutableData *buf;
        NSAutoreleasePool *pool;
        int i, j;

        pool = [[NSAutoreleasePool alloc] init];
        buf = [NSMutableData data];

        [buf appendData:[NSData randomDataOfLength:128]];
        [buf appendData:[@"This is test data." dataUsingEncoding:NSASCIIStringEncoding]];

        for(i = 0; i < 100; i ++) {
            NSData *blob = [buf sha1Signature];
            for(j = 0; j < 100; j ++) {
                [buf appendData:[[NSString stringWithFormat:@"Blah, blah, blah. (%d, %d)", i, j] dataUsingEncoding:NSASCIIStringEncoding]];
                [buf appendData:blob];
            }
        }

        for(i = 0; i < 4; i ++) {
            NSData *blob = [buf copy];
            [buf appendData:[[NSString stringWithFormat:@"Foo, bar, baz (%d)", i] dataUsingEncoding:NSASCIIStringEncoding]];
            [buf appendData:blob];
            [blob release];
        }

        someData = [buf copy];
        [pool release];

        NSLog(@"Test data: %lu bytes", [someData length]);
    }
}

// Test cases

- (void)setUp
{
    runningProcs = [[NSConditionLock alloc] initWithCondition:0];
    readerStates = [[NSMutableArray alloc] init];
    dataStream = nil;
}

- (void)tearDown
{
    [runningProcs release];
    runningProcs = nil;
    [readerStates release];
    readerStates = nil;
    [dataStream release];
    dataStream = nil;
    [inputData release];
    inputData = nil;
}

- (void)spawnReaders:(NSString *)action count:(unsigned)procCount
{
    unsigned procIndex;
    
    [runningProcs lock];
    for(procIndex = 0; procIndex < procCount; procIndex ++) {
        NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
        [info setObject:action forKey:@"action"];
        [readerStates addObject:info];
        [NSThread detachNewThreadSelector:@selector(readerThread:) toTarget:self withObject:info];
        [info release];
    }
    [runningProcs unlockWithCondition:[readerStates count]];
}

#if 0
- (void)spawnRunLoopReaders:(unsigned)procCount
{
    unsigned procIndex;

    [otherLoopLock lock];
    [otherLoopLock unlockWithCondition:0];

    [NSThread detachNewThreadSelector:@selector(readerRunLoop) toTarget:self withObject:nil];

    [otherLoopLock lockWhenCondition:1];
    [runningProcs lock];

    for(procIndex = 0; procIndex < procCount; procIndex ++) {
        NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
        OWDataStreamCursor *curs = [dataStream newCursor];
        [info setObject:action forKey:@"action"];
        [info setObject:curs forKey:@"cursor"];
        [readerStates addObject:info];
        [curs scheduleInQueue: ... ];
        [info release];
    }
    [runningProcs unlockWithCondition:[readerStates count]];
}
#endif

- (void)readerThread:(NSMutableDictionary *)info
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSInteger newCondition;

    NS_DURING {
        [self performSelector:NSSelectorFromString([info objectForKey:@"action"]) withObject:info];
        [info setObject:[NSNumber numberWithBool:YES] forKey:@"done"];
    } NS_HANDLER {
        [info setObject:localException forKey:@"exception"];
    } NS_ENDHANDLER;

    [pool release];

    [runningProcs lock];
    newCondition = [runningProcs condition] - 1;
    [runningProcs unlockWithCondition:newCondition];
}

- (void)verifyResults
{
    NSUInteger procIndex;

    [runningProcs lockWhenCondition:0];
    [runningProcs unlock];

    for(procIndex = 0; procIndex < [readerStates count]; procIndex ++) {
        NSDictionary *info = [readerStates objectAtIndex:procIndex];
        NSString *procDesc = [NSString stringWithFormat:@"Thread %lu", procIndex];

        if ([info objectForKey:@"done"]) {
            XCTAssertNil([info objectForKey:@"exception"], @"%@", procDesc);
            XCTAssertEqual([info objectForKey:@"data"], inputData, @"%@", procDesc);
        } else if ([info objectForKey:@"exception"]) {
            XCTFail(@"Exception %@", info);
        } else {
            XCTFail(@"Proc %lu has bad state: %@", procIndex, [info description]);
        }
    }

}

- (void)smallReader:(NSMutableDictionary *)info
{
    OWDataStreamCursor *cursor = [dataStream createCursor];
    NSMutableData *buf;

    buf = [[NSMutableData alloc] init];
    [info setObject:buf forKey:@"data"];
    [buf autorelease];
    while (![cursor isAtEOF]) {
        NSUInteger staccato = random() % 256;
        NSUInteger avail = [dataStream bufferedDataLength] - [cursor currentOffset];
        NSData *piece = [cursor readBytes: MAX(MIN(avail, staccato), 1UL)];
        [buf appendData:piece];
    }
}

- (void)largeReader:(NSMutableDictionary *)info
{
    OWDataStreamCursor *cursor = [dataStream createCursor];
    NSMutableData *buf;

    buf = [[NSMutableData alloc] init];
    [info setObject:buf forKey:@"data"];
    [buf autorelease];
    while (1) {
        NSData *piece = [cursor readData];
        if (piece == nil)
            break;
        [buf appendData:piece];
    }
}

- (void)testSmallReaders
{
    XCTAssertTrue(dataStream == nil);
    XCTAssertTrue(runningProcs != nil);

    inputData = [[@"This is a test" dataUsingEncoding:NSASCIIStringEncoding] retain];

    dataStream = [[OWDataStream alloc] initWithLength:[inputData length]];
    [dataStream writeData:inputData];
    [dataStream dataEnd];

    [readerStates removeAllObjects];
    [self spawnReaders:@"smallReader:" count:5];
    [self verifyResults];

    [inputData release];
    inputData = [someData retain];
    [dataStream release];
    dataStream = [[OWDataStream alloc] init];
    [dataStream writeData:inputData];

    [readerStates removeAllObjects];
    [self spawnReaders:@"smallReader:" count:5];
    [self spawnReaders:@"largeReader:" count:2];

    usleep(10000);
    [dataStream dataEnd];
    
    [self verifyResults];

    [dataStream release];
    dataStream = nil;
    [inputData release];
    inputData = nil;
}

- (void)testChunkyWriter
{
    unsigned writePos;
    
    XCTAssertTrue(dataStream == nil);
    XCTAssertTrue(runningProcs != nil);

    dataStream = [[OWDataStream alloc] init];
    inputData = [someData retain];

    [readerStates removeAllObjects];
    [self spawnReaders:@"smallReader:" count:6];
    [self spawnReaders:@"largeReader:" count:3];

    writePos = 0;
    while (writePos < [inputData length]) {
        NSUInteger staccato = random() % 256;
        NSUInteger fl2 = random() & 0xF;
        NSUInteger bufAvail;
        char *bufptr;
        
        if (staccato > 128)
            staccato = random() % 0x5000;
        if (staccato+writePos > [inputData length])
            staccato = [inputData length] - writePos;

        bufAvail = [dataStream appendToUnderlyingBuffer:(void **)&bufptr];
        staccato = MIN(staccato, bufAvail);
        [inputData getBytes:bufptr range:(NSRange){writePos, staccato}];
        writePos += staccato;
        if (fl2 & 0x01)
            usleep(random() % 256);
        [dataStream wroteBytesToUnderlyingBuffer:staccato];
        if (fl2 & 0x02)
            usleep(random() % 256);
    }
    [dataStream dataEnd];
    
    [self verifyResults];

    [inputData release];
    inputData = nil;
    [dataStream release];
    dataStream = nil;
}

@end


