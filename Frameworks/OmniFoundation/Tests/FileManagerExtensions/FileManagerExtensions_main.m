// Copyright 1999-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OmniBase.h>
#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/system.h>

RCS_ID("$Id$")

static void Test(void);

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    Test();

    [pool release];
    return 0;
}

@interface NSFileManager (OldImplementation)
- (NSString *)oldUniqueFilenameFromName:(NSString *)filename;
- (NSString *)oldExistingPortionOfPath:(NSString *)path;
@end

static NSFileManager *fileManager = nil;

void TestUniqueFilename(NSString *filename)
{
    NSString *oldResult, *newResult;

    oldResult = [fileManager oldUniqueFilenameFromName:filename];
    newResult = [fileManager uniqueFilenameFromName:filename];
    NSLog(@"%@ -> %@", filename, newResult);
    if (![oldResult isEqualToString:newResult])
        NSLog(@"    oldResult -> %@", oldResult);
    if (![@"Test" writeToFile:newResult atomically:NO])
        perror("Create file");
}

static void TestUniqueFilenames(void)
{
    [fileManager createPathToFile:@"/tmp/FileManagerExtensions/foo.txt" attributes:nil];
    TestUniqueFilename(@"/tmp/FileManagerExtensions/foo.txt");
    TestUniqueFilename(@"/tmp/FileManagerExtensions/foo.txt");
    TestUniqueFilename(@"/tmp/FileManagerExtensions/foo.txt");
    TestUniqueFilename(@"/tmp/FileManagerExtensions/foo.txt");
    TestUniqueFilename(@"/tmp/FileManagerExtensions/foo");
    TestUniqueFilename(@"/tmp/FileManagerExtensions/foo");
    TestUniqueFilename(@"/tmp/FileManagerExtensions/foo");
    TestUniqueFilename(@"/tmp/FileManagerExtensions/foo");
    TestUniqueFilename(@"/tmp/FileManagerExtensions/foo.tar.gz");
    TestUniqueFilename(@"/tmp/FileManagerExtensions/foo.tar.gz");
    TestUniqueFilename(@"/tmp/FileManagerExtensions/foo.tar.gz");
    TestUniqueFilename(@"/tmp/FileManagerExtensions/foo.tar.gz");
    TestUniqueFilename(@"FileManagerExtensionsTest");
    TestUniqueFilename(@"FileManagerExtensionsTest");
    TestUniqueFilename(@"FileManagerExtensionsTest");
    TestUniqueFilename(@"FileManagerExtensionsTest");
    TestUniqueFilename(@"FileManagerExtensionsTest.txt");
    TestUniqueFilename(@"FileManagerExtensionsTest.txt");
    TestUniqueFilename(@"FileManagerExtensionsTest.txt");
    TestUniqueFilename(@"FileManagerExtensionsTest.txt");
    TestUniqueFilename(@"/FileManagerExtensionsTest.txt");
    TestUniqueFilename(@"/FileManagerExtensionsTest.txt");
    TestUniqueFilename(@"/FileManagerExtensionsTest.txt");
    TestUniqueFilename(@"/FileManagerExtensionsTest.txt");
}

static void TestExistingPortionOfPath(NSString *path)
{
    NSString *oldResult, *newResult;

    path = [path stringByExpandingTildeInPath];
    oldResult = [fileManager oldExistingPortionOfPath:path];
    newResult = [fileManager existingPortionOfPath:path];
    NSLog(@"%@ -> %@", path, newResult);
    if (![oldResult isEqualToString:newResult])
        NSLog(@"    oldResult -> %@", oldResult);
}

static void TestExistingPortionOfPaths(void)
{
    TestExistingPortionOfPath(@"/");
    TestExistingPortionOfPath(@"/tmp/kc/1234/5678");
    TestExistingPortionOfPath(@"/tmp/OmniWeb/1234/5678");
    TestExistingPortionOfPath(@"/Local/Library");
    TestExistingPortionOfPath(@"/Local/Library/Web/products/omniweb");
    TestExistingPortionOfPath(@"~");
    TestExistingPortionOfPath(@"~/Library/Web");
    TestExistingPortionOfPath(@"~/Library/Test/Web");
    TestExistingPortionOfPath(@"~/Library/OmniWeb/Bookmarks.html");
    TestExistingPortionOfPath(@"");
}

static void Test(void)
{
    fileManager = [NSFileManager defaultManager];
    TestUniqueFilenames();
    TestExistingPortionOfPaths();
}

@implementation NSFileManager (OldImplementation)

- (NSString *)oldUniqueFilenameFromName:(NSString *)filename;
{
    int testFD;
    NSRange lastPathComponentRange, periodRange;

    testFD = open([self fileSystemRepresentationWithPath:filename], O_EXCL | O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (testFD != -1) {
	close(testFD);
	return filename;
    }
#warning -uniqueFilenameFromName: does not work properly on Windows
    lastPathComponentRange = [filename rangeOfString:@"/" options:NSBackwardsSearch];
    if (lastPathComponentRange.length != 0) {
	lastPathComponentRange.location++;
	lastPathComponentRange.length = [filename length] - lastPathComponentRange.location;
    }
    if (lastPathComponentRange.length == 0)
        lastPathComponentRange = NSMakeRange(0, [filename length]);

    periodRange = [filename rangeOfString:@"." options:0 range:lastPathComponentRange];
    if (periodRange.length != 0) {
	filename = [self tempFilenameFromHashesTemplate:[NSString stringWithFormat:@"%@-######.%@", [filename substringToIndex:periodRange.location], [filename substringFromIndex:periodRange.location + 1]]];
    } else {
	filename = [self tempFilenameFromHashesTemplate:[NSString stringWithFormat:@"%@-######", filename]];
    }

    return filename;
}

- (NSString *)oldExistingPortionOfPath:(NSString *)path;
{
    NSArray *pathComponents;
    unsigned int goodComponentsCount, componentCount;

    pathComponents = [path pathComponents];
    componentCount = [pathComponents count];
    for (goodComponentsCount = 0; goodComponentsCount < componentCount; goodComponentsCount++) {
        BOOL isDirectory;

        if (![self fileExistsAtPath:[NSString pathWithComponents:[pathComponents subarrayWithRange:NSMakeRange(0, goodComponentsCount + 1)]] isDirectory:&isDirectory])
            break;

        // Break early if we hit a non-directory before the end of the path
        if (!isDirectory && (goodComponentsCount < componentCount-1))
            break;
    }

    if (goodComponentsCount == 0)
        return @"";
    else if (goodComponentsCount == 1)
        return @"/";
    else if (goodComponentsCount == componentCount)
        return path;
    else
        return [[NSString pathWithComponents:[pathComponents subarrayWithRange:NSMakeRange(0, goodComponentsCount)]] stringByAppendingString:@"/"];
}

@end
