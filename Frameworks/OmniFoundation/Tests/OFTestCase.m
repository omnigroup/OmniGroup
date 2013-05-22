// Copyright 2008, 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniBase/rcsid.h>

// This import isn't needed for this file, but serves as a test of whether the headers are properly #ifdef in OmniFoundation.h
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation OFTestCase

+ (SenTest *)dataDrivenTestSuite
{    
    NSString *casesPath = [[NSBundle bundleForClass:self] pathForResource:[self description] ofType:@"tests"];
    NSDictionary *allTestCases = [NSDictionary dictionaryWithContentsOfFile:casesPath];
    if (!allTestCases) {
        [NSException raise:NSGenericException format:@"Unable to load test cases for class %@ from path: \"%@\"", [self description], casesPath];
        return nil;
    }
    
    SenTestSuite *suite = OB_AUTORELEASE([[SenTestSuite alloc] initWithName:[casesPath lastPathComponent]]);
    
    [allTestCases enumerateKeysAndObjectsUsingBlock:^(NSString *methodName, NSArray *cases, BOOL *stop) {
        [suite addTest:[self testSuiteForMethod:methodName cases:cases]];
    }];
    
    return suite;
}

+ (SenTest *)testSuiteForMethod:(NSString *)methodName cases:(NSArray *)testCases
{
    SEL method = NSSelectorFromString([methodName stringByAppendingString:@":"]);
    if (method == NULL || ![self instancesRespondToSelector:method]) {
        [NSException raise:NSGenericException format:@"Unimplemented method -[%@ %@:] referenced in test case file", [self description], methodName];
    }
    
    return [self testSuiteNamed:methodName usingSelector:method cases:testCases];
}

+ (SenTest *)testSuiteNamed:(NSString *)suiteName usingSelector:(SEL)testSelector cases:(NSArray *)testCases;
{
    NSMethodSignature *methodSignature = [self instanceMethodSignatureForSelector:testSelector];
    if (!methodSignature ||
        [methodSignature numberOfArguments] != 3 || /* 3 args: self, _cmd, and the test case */
        strcmp([methodSignature methodReturnType], "v") != 0) {
        [NSException raise:NSGenericException format:@"Method -[%@ %@] referenced in test case file has incorrect signature", [self description], NSStringFromSelector(testSelector)];
    }
    
    SenTestSuite *suite = OB_AUTORELEASE([[SenTestSuite alloc] initWithName:suiteName]);
    
    for (id testArguments in testCases) {
        NSInvocation *testInvocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        [testInvocation retainArguments]; // Do this before setting the argument so it gets captured in ARC mode
        [testInvocation setSelector:testSelector];
        [testInvocation setArgument:(void *)&testArguments atIndex:2];
        
        OFTestCase *testCase = [self testCaseWithInvocation:testInvocation];
        [suite addTest:testCase];
    }
    
    return suite;
} 

- (NSString *)name
{
    /* For the specific case of -testSomething:(NSString *)what, include the value of what in the test's name. */
    NSInvocation *inv = [self invocation];
    NSMethodSignature *signature = [inv methodSignature];
    if (signature && [signature numberOfArguments] == 3) {
        const char *argt = [signature getArgumentTypeAtIndex:2];
        if (argt && (argt[0] == _C_ID)) {
            id argv = nil;
            NSString *argstr;
            [inv getArgument:&argv atIndex:2];
            if (!argv) {
                argstr = @"nil";
            } else if ([argv isKindOfClass:[NSString class]]) {
                argstr = [NSString stringWithFormat:@"@\"%@\"", argv];
            } else {
                return [super name];
            }
            return [NSString stringWithFormat:@"-[%@ %@%@]", NSStringFromClass([self class]), NSStringFromSelector([inv selector]), argstr];
        }
    }
    return [super name];
}

@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <OmniBase/NSError-OBExtensions.h>

void OFDiffData(SenTestCase *testCase, NSData *expected, NSData *actual)
{
    NSString *name = [testCase name];
    
    __autoreleasing NSError *error = nil;
    NSString *expectedPath = [[NSFileManager defaultManager] scratchFilenameNamed:[@"expected-" stringByAppendingString:name] error:&error];
    if (!expectedPath) {
        NSLog(@"Unable to create scratch path: %@", [error toPropertyList]);
        return;
    }
    
    NSString *actualPath = [[NSFileManager defaultManager] scratchFilenameNamed:[@"actual-" stringByAppendingString:name] error:&error];
    if (!actualPath) {
        NSLog(@"Unable to create scratch path: %@", [error toPropertyList]);
        return;
    }
    
    if (![expected writeToURL:[NSURL fileURLWithPath:expectedPath] options:0 error:&error]) {
        NSLog(@"Unable to write scratch file to %@: %@", expectedPath, [error toPropertyList]);
        return;
    }
    if (![actual writeToURL:[NSURL fileURLWithPath:actualPath] options:0 error:&error]) {
        NSLog(@"Unable to write scratch file to %@: %@", actualPath, [error toPropertyList]);
        return;
    }
    
    NSLog(@"Diffs:\nopendiff '%@' '%@'", expectedPath, actualPath);
    NSTask *diffTask = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/diff" arguments:[NSArray arrayWithObjects:@"-u", expectedPath, actualPath, nil]];
    [diffTask waitUntilExit]; // result should be 1 if they are different, so not worth checking
}

#endif

static BOOL _addRelativePaths(NSMutableSet *relativePaths, NSString *base, OFDiffFilesPathFilter pathFilter, NSError **outError)
{
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:base error:outError];
    if (!attributes)
        return NO;
    
    if (OFISEQUAL([attributes fileType], NSFileTypeDirectory)) {
        NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:base];
        for (NSString *path in dirEnum) {
            if (!pathFilter || pathFilter(path))
                [relativePaths addObject:path];
        }
    } else {
        // plain file
        if (!pathFilter || pathFilter(base))
            [relativePaths addObject:@""];
    }
    
    return YES;
}

static BOOL _OFCheckFilesSame(SenTestCase *self, NSString *path1, NSString *path2, BOOL requireSame, OFDiffFilesPathFilter pathFilter)
{
    __autoreleasing NSError *error = nil;

    // Collect all the files, as relative paths from the two inputs
    NSMutableSet *files1 = [NSMutableSet set];
    OBShouldNotError(_addRelativePaths(files1, path1, pathFilter, &error));
    if ([files1 count] == 0) {
        if (requireSame)
            STFail(@"No files at \"%@\"", path1);
        return NO;
    }
    
    NSMutableSet *files2 = [NSMutableSet set];
    OBShouldNotError(_addRelativePaths(files2, path2, pathFilter, &error));
    if ([files2 count] == 0) {
        if (requireSame)
            STFail(@"No files at \"%@\"", path2);
        return NO;
    }
    
    // Build a map between entries
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    
    // TDOO: Delegate hook like OAT's diff.rb
    
    // Default maps from 1->2. Have to go over both sets in case one side is missing a file.
    for (NSString *entry in files1)
        [map setObject:[path2 stringByAppendingPathComponent:entry] forKey:[path1 stringByAppendingPathComponent:entry]];
    for (NSString *entry in files2)
        [map setObject:[path2 stringByAppendingPathComponent:entry] forKey:[path1 stringByAppendingPathComponent:entry]];
    
    // Now compare each mapping.
    for (NSString *map1 in [[map allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *map2 = [map objectForKey:map1];
        
        // TODO: Support for comparing compressed files, formatting XML, etc.
        
        NSDictionary *attributes1 = [[NSFileManager defaultManager] attributesOfItemAtPath:map1 error:&error];
        if (!attributes1) {
            if (requireSame)
                STFail(@"Unable to read attributes");
            return NO;
        }
        NSDictionary *attributes2 = [[NSFileManager defaultManager] attributesOfItemAtPath:map1 error:&error];
        if (!attributes2) {
            if (requireSame)
                STFail(@"Unable to read attributes");
            return NO;
        }
        
        NSString *fileType1 = [attributes1 fileType];
        NSString *fileType2 = [attributes2 fileType];
        
        if (OFNOTEQUAL(fileType1, fileType2)) {
            if (requireSame)
                STFail(@"One file is of type \"%@\" and the other \"%@\"", fileType1, fileType2);
            return NO;
        }
        
        if (OFISEQUAL(fileType1, NSFileTypeRegular)) {
            NSData *data1 = [[NSData alloc] initWithContentsOfFile:map1 options:0 error:&error];
            if (!data1) {
                if (requireSame)
                    STFail(@"Unable to read data");
                return NO;
            }
            
            NSData *data2 = [[NSData alloc] initWithContentsOfFile:map2 options:0 error:&error];
            if (!data2) {
                OB_RELEASE(data1);
                if (requireSame)
                    STFail(@"Unable to read data");
                return NO;
            }
            
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
            if (OFNOTEQUAL(data1, data2)) {
                OB_RELEASE(data1);
                OB_RELEASE(data2);
                if (requireSame)
                    STFail(@"Files differ!\ndiff \"%@\" \"%@\"", map1, map2);
                return NO;
            }
#else
            if (requireSame)
                OFDataShouldBeEqual(data1, data2);
#endif
            
            OB_RELEASE(data1);
            OB_RELEASE(data2);
        } else if (OFISEQUAL(fileType1, NSFileTypeDirectory)) {
            // could maybe compare attributes...
        } else if (OFISEQUAL(fileType1, NSFileTypeSymbolicLink)) {
            NSString *destination1 = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:map1 error:&error];
            if (!destination1)
                return NO;
            NSString *destination2 = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:map2 error:&error];
            if (!destination1)
                return NO;
            
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
            if (OFNOTEQUAL(destination1, destination2)) {
                if (requireSame)
                    STFail(@"Symlink destinations differ!\n"
                           "\"%@\" -> \"%@\"\n"
                           "\"%@\" -> \"%@\"\n", map1, destination1, map2, destination2);
                return NO;
            }
#else
            if (requireSame)
                STAssertEqualObjects(destination1, destination2, @"Link destinations should be the same");
#endif
        } else {
            if (requireSame)
                STFail(@"Don't know how to compare files of type \"%@\"", fileType1);
            return NO;
        }
    }
    
    return YES;
}

static BOOL OFCheckFilesSame(SenTestCase *self, NSString *path1, NSString *path2, BOOL requireSame, OFDiffFilesPathFilter pathFilter)
{
    OBPRECONDITION(path1);
    OBPRECONDITION(path2);
    OBPRECONDITION(OFNOTEQUAL(path1, path2), @"Why compare the file against itself?");
        
    // Use file coordination to prevent incoming edits from confusing us with partially changed file state (like an incoming rename from OmniPresence during our unit tests).
    // This can potentially hang, though, if some other code in the unit test has a file presenter that will get called and will block on the main queue somehow.
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSURL *fileURL1 = [NSURL fileURLWithPath:path1];
    NSURL *fileURL2 = [NSURL fileURLWithPath:path2];
    
    __block BOOL result = NO;
    
    NSArray *readFileURLs = [NSArray arrayWithObjects:fileURL1, fileURL2, nil];
    __autoreleasing NSError *error;
    BOOL success = [coordinator prepareToReadItemsAtURLs:readFileURLs withChanges:YES error:&error byAccessor:^BOOL(NSError **outPrepareError){
        return [coordinator readItemAtURL:fileURL1 withChanges:YES error:outPrepareError byAccessor:^BOOL(NSURL *newURL1, NSError **outRead1Error) {
            return [coordinator readItemAtURL:fileURL2 withChanges:YES error:outRead1Error byAccessor:^BOOL(NSURL *newURL2, NSError **outRead2Error) {
                result = _OFCheckFilesSame(self, [[newURL1 absoluteURL] path], [[newURL2 absoluteURL] path], requireSame, pathFilter);
                return YES;
            }];
        }];
    }];

    STAssertTrue(success, @"File coordination failed");
    return result;
}

BOOL OFSameFiles(SenTestCase *self, NSString *path1, NSString *path2, OFDiffFilesPathFilter pathFilter)
{
    return OFCheckFilesSame(self, path1, path2, NO/*requireSame*/, pathFilter);
}


void OFDiffFiles(SenTestCase *self, NSString *path1, NSString *path2, OFDiffFilesPathFilter pathFilter)
{
    OFCheckFilesSame(self, path1, path2, YES/*requireSame*/, pathFilter);
}

