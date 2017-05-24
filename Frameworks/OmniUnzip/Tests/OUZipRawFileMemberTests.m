// Copyright 2017 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OBTestCase.h"

#import <OmniFoundation/OmniFoundation.h>
#import <OmniUnzip/OmniUnzip.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC;

@interface OUZipRawFileMemberTests : OBTestCase
@end

@implementation OUZipRawFileMemberTests

- (NSString *)uniqueTemporaryPathForZipWithKey:(NSString *)key;
{
    NSString *identifier = OFXMLCreateID();
    NSString *filename = [NSString stringWithFormat:@"OUZipRawFileMemberTest-%@-%@.zip", key, identifier];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
}

#pragma mark Tests

- (void)testRawMemberAppendRespectsFilenamePrefix;
{
    NSString *sourcePath = [self uniqueTemporaryPathForZipWithKey:@"source"];
    NSString *destinationPath = [self uniqueTemporaryPathForZipWithKey:@"destination"];
    NSError *error = nil;
    
    NSData *contents = [@"some contents" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *name = @"file.txt";
    
    NSString *prefix = @"foo/bar";
    NSString *prefixedName = [NSString stringWithFormat:@"%@/%@", prefix, name];
    
    {
        // Create a source zip file out of thin air
        OUZipArchive *sourceZip = [[OUZipArchive alloc] initWithPath:sourcePath error:&error];
        XCTAssertNotNil(sourceZip);
        XCTAssertNil(error);
        
        OUZipMember *sourceMember = [[OUZipFileMember alloc] initWithName:name date:[NSDate date] contents:contents];
        OBShouldNotError([sourceMember appendToZipArchive:sourceZip fileNamePrefix:nil error:&error]);
        
        OBShouldNotError([sourceZip close:&error]);
    }
    
    {
        // Re-read the source zip file back so we get file.txt as an unzip entry
        OUUnzipArchive *sourceUnzip = [[OUUnzipArchive alloc] initWithPath:sourcePath error:&error];
        XCTAssertNotNil(sourceUnzip);
        XCTAssertNil(error);
        
        OUUnzipEntry *sourceEntry = [sourceUnzip entryNamed:name];
        XCTAssertNotNil(sourceEntry);
        
        // Create another zip at the destination path and copy file.txt to it, using a raw member to copy the unzip entry *with a prefix*
        OUZipArchive *destinationZip = [[OUZipArchive alloc] initWithPath:destinationPath error:&error];
        XCTAssertNotNil(destinationZip);
        XCTAssertNil(error);
        
        OUZipMember *destinationMember = [[OUZipRawFileMember alloc] initWithEntry:sourceEntry archive:sourceUnzip];
        OBShouldNotError([destinationMember appendToZipArchive:destinationZip fileNamePrefix:prefix error:&error]);
        
        OBShouldNotError([destinationZip close:&error]);
    }
    
    {
        // Now re-read the destination zip, checking that file.txt was copied to an appropriate (prefixed) entry and that its contents are unchanged when unzipped
        OUUnzipArchive *destinationUnzip = [[OUUnzipArchive alloc] initWithPath:destinationPath error:&error];
        XCTAssertNotNil(destinationUnzip);
        XCTAssertNil(error);
        
        OUUnzipEntry *destinationEntry = [destinationUnzip entryNamed:prefixedName];
        XCTAssertNotNil(destinationEntry);
        
        NSData *rereadContents = [destinationUnzip dataForEntry:destinationEntry error:&error];
        XCTAssertEqualObjects(contents, rereadContents);
        XCTAssertNil(error);
    }
    
    {
        // Clean up
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtPath:sourcePath error:NULL];
        [fileManager removeItemAtPath:destinationPath error:NULL];
    }
}

@end
