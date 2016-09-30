// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <XCTest/XCTest.h>

#import <OmniUnzip/OmniUnzip.h>

#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>

RCS_ID("$Id$");

@interface OUUnzipArchiveTests : XCTestCase

@end

#pragma mark -

@implementation OUUnzipArchiveTests

- (void)setUp;
{
    [super setUp];
}

- (void)tearDown;
{
    [super tearDown];
}

- (void)testDataExtraction;
{
    const NSUInteger dataLength = 4 * 1024 * 1024;
    NSData *data = [NSData randomDataOfLength:dataLength];
    
    NSFileWrapper *fileWrapper = [[NSFileWrapper alloc] initRegularFileWithContents:data];
    fileWrapper.preferredFilename = @"TEST_DATA";
    
    NSError *error = nil;
    NSString *temporaryPath = [[NSFileManager defaultManager] temporaryDirectoryForFileSystemContainingPath:@"/" error:&error];
    XCTAssertNotNil(temporaryPath);
    
    NSString *filename = [NSString stringWithFormat:@"%@.zip", [[NSUUID UUID] UUIDString]];
    temporaryPath = [temporaryPath stringByAppendingPathComponent:filename];
    XCTAssertTrue([OUZipArchive createZipFile:temporaryPath fromFileWrappers:@[fileWrapper] error:&error]);
    
    OUUnzipArchive *archive = [[OUUnzipArchive alloc] initWithPath:temporaryPath error:&error];
    XCTAssertNotNil(archive);
    
    OUUnzipEntry *entry = [archive entryNamed:fileWrapper.preferredFilename];
    XCTAssertNotNil(entry);
    
    NSData *oneShotData = [archive dataForEntry:entry error:&error];
    XCTAssertNotNil(oneShotData);
    XCTAssertEqualObjects(data, oneShotData);
    
    NSInputStream *inputStream = [archive inputStreamForEntry:entry error:&error];
    XCTAssertNotNil(inputStream);
    
    NSMutableData *chunkedData = [NSMutableData data];
    
    [inputStream open];
    XCTAssert(inputStream.streamStatus == NSStreamStatusOpen);
    
    while (inputStream.streamStatus == NSStreamStatusOpen) {
        const NSUInteger BUFFER_LENGTH = 143;
        uint8_t buffer[BUFFER_LENGTH];
        NSInteger bytesRead = [inputStream read:buffer maxLength:BUFFER_LENGTH];
        [chunkedData appendBytes:buffer length:bytesRead];
    }
    
    [inputStream close];

    XCTAssertEqualObjects(data, chunkedData);
    
    [[NSFileManager defaultManager] removeItemAtPath:temporaryPath error:NULL];
}

- (void)testFoundationStreamReading;
{
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];

    for (NSInteger i = 0; i < 10000; i++) {
        NSString *key = [[NSUUID UUID] UUIDString];
        NSString *value = [NSString stringWithFormat:@"value %ld", i];
        plist[key] = value;
    }
    
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    XCTAssertNotNil(data);

    NSFileWrapper *fileWrapper = [[NSFileWrapper alloc] initRegularFileWithContents:data];
    fileWrapper.preferredFilename = @"TEST.plist";
    
    NSString *temporaryPath = [[NSFileManager defaultManager] temporaryDirectoryForFileSystemContainingPath:@"/" error:&error];
    XCTAssertNotNil(temporaryPath);
    
    NSString *filename = [NSString stringWithFormat:@"%@.zip", [[NSUUID UUID] UUIDString]];
    temporaryPath = [temporaryPath stringByAppendingPathComponent:filename];
    XCTAssertTrue([OUZipArchive createZipFile:temporaryPath fromFileWrappers:@[fileWrapper] error:&error]);
    
    OUUnzipArchive *archive = [[OUUnzipArchive alloc] initWithPath:temporaryPath error:&error];
    XCTAssertNotNil(archive);
    
    OUUnzipEntry *entry = [archive entryNamed:fileWrapper.preferredFilename];
    XCTAssertNotNil(entry);

    NSInputStream *inputStream = [archive inputStreamForEntry:entry error:&error];
    XCTAssertNotNil(inputStream);
    
    [inputStream open];
    XCTAssert(inputStream.streamStatus == NSStreamStatusOpen);
    
    id extractedPlist = [NSPropertyListSerialization propertyListWithStream:inputStream options:NSPropertyListImmutable format:NULL error:&error];
    XCTAssertNotNil(extractedPlist);
    XCTAssertEqualObjects(plist, extractedPlist);
    
    [inputStream close];
    XCTAssert(inputStream.streamStatus == NSStreamStatusClosed);
}

@end
