// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

@import OmniBase;
@import OmniFoundation;

RCS_ID("$Id$")

OB_REQUIRE_ARC

NS_ASSUME_NONNULL_BEGIN

@implementation OFTestCase

+ (XCTest *)dataDrivenTestSuite
{    
    NSString *casesPath = [[NSBundle bundleForClass:self] pathForResource:[self description] ofType:@"tests"];
    NSDictionary *allTestCases = [NSDictionary dictionaryWithContentsOfFile:casesPath];
    if (!allTestCases) {
        [NSException raise:NSGenericException format:@"Unable to load test cases for class %@ from path: \"%@\"", [self description], casesPath];
        return nil;
    }
    
    XCTestSuite *suite = [[XCTestSuite alloc] initWithName:[casesPath lastPathComponent]];
    
    [allTestCases enumerateKeysAndObjectsUsingBlock:^(NSString *methodName, NSArray *cases, BOOL *stop) {
        [suite addTest:[self testSuiteForMethod:methodName cases:cases]];
    }];
    
    return suite;
}

+ (XCTest *)testSuiteForMethod:(NSString *)methodName cases:(NSArray *)testCases
{
    SEL method = NSSelectorFromString([methodName stringByAppendingString:@":"]);
    if (method == NULL || ![self instancesRespondToSelector:method]) {
        [NSException raise:NSGenericException format:@"Unimplemented method -[%@ %@:] referenced in test case file", [self description], methodName];
    }
    
    return [self testSuiteNamed:methodName usingSelector:method cases:testCases];
}

+ (XCTest *)testSuiteNamed:(NSString *)suiteName usingSelector:(SEL)testSelector cases:(NSArray *)testCases;
{
    NSMethodSignature *methodSignature = [self instanceMethodSignatureForSelector:testSelector];
    if (!methodSignature ||
        [methodSignature numberOfArguments] != 3 || /* 3 args: self, _cmd, and the test case */
        strcmp([methodSignature methodReturnType], "v") != 0) {
        [NSException raise:NSGenericException format:@"Method -[%@ %@] referenced in test case file has incorrect signature", [self description], NSStringFromSelector(testSelector)];
    }
    
    XCTestSuite *suite = [[XCTestSuite alloc] initWithName:suiteName];
    
    for (__unsafe_unretained id testArguments in testCases) {
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
            __unsafe_unretained id argv = nil;
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

// MARK:- Fixture driven test support

/**

 Subclasses can override `+defaultTestSuite` to call this with their directory of fixtures and a selector to call, which should take one argument (the URL to the individual file to process).

 They may additionally override `-name` to call `+nameForFixtureDrivenTestCase:`.

 */

+ (void)addFixtureDrivenTestsToSuite:(XCTestSuite *)suite fixturesURL:(NSURL *)fixturesURL processSelector:(SEL)processSelector;
{
    NSError *error = nil;
    NSArray <NSURL *> *fileURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:fixturesURL includingPropertiesForKeys:nil options:0 error:&error];
    if (!fileURLs) {
        NSLog(@"Error looking for files in %@: %@", fixturesURL, [error toPropertyList]);
        [NSException raise:NSInternalInconsistencyException format:@"Unable to find files in fixtures %@.", fixturesURL];
    }

    // otest is lame and doesn't let us filter dynamic suites, as far as I can tell... and it hates arguments it doesn't understand, so pass this in the environment.
    NSString *onlyTestNamed = [[[NSProcessInfo processInfo] environment] objectForKey:@"OnlyTestNamed"];

    NSMethodSignature *methodSignature = [self instanceMethodSignatureForSelector:processSelector];
    if (!methodSignature || [methodSignature numberOfArguments] != 3 || /* 4 args: self, _cmd, fileURL */
        strcmp([methodSignature methodReturnType], "v") != 0) {
        [NSException raise:NSGenericException format:@"Method -[%@ %@] has incorrect signature", NSStringFromClass(self), NSStringFromSelector(processSelector)];
    }

    // For each output, make a test case that converts the input to that output (might be more than one output for each input).
    for (NSURL *fileURL in fileURLs) {
        NSInvocation *testInvocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        [testInvocation setSelector:processSelector];
        [testInvocation setArgument:(void *)&fileURL atIndex:2];
        [testInvocation retainArguments];

        OFTestCase *testCase = [self testCaseWithInvocation:testInvocation];

        if (!onlyTestNamed || OFISEQUAL([testCase name], onlyTestNamed))
            [suite addTest:testCase];
    }
}

+ (NSURL *)fixturesURL;
{
    NSURL *baseFixtures = [[NSBundle bundleForClass:self] URLForResource:@"fixtures" withExtension:@""];
    if (!baseFixtures) {
        [NSException raise:NSInternalInconsistencyException format:@"Missing fixtures resource."];
    }

    NSString *className = NSStringFromClass(self);
    NSRange dotRange = [className rangeOfString:@"."];
    if (dotRange.location != NSNotFound) {
        // Swift class with module prefix
        className = [className substringFromIndex: NSMaxRange(dotRange)];
    }

    return [baseFixtures URLByAppendingPathComponent:className];
}

+ (NSString *)nameForFixtureDrivenTestCase:(OFTestCase *)testCase;
{
    NSInvocation *invocation = [testCase invocation];

    // This file is using ARC and we don't want this variable to be `strong` since we are modifying it w/o strong semantics here (which would cause an extra -release on the NSURL each time this method was called!)
    __unsafe_unretained NSURL *output = nil;
    [invocation getArgument:&output atIndex:2];

    return [output lastPathComponent];
}

@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

void OFDiffData(XCTestCase *testCase, NSData *expected, NSData *actual)
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

void OFDiffDataFiles(XCTestCase *testCase, NSString *expectedPath, NSString *actualPath)
{    
    NSLog(@"Diffs:\nopendiff '%@' '%@' -merge '%@'", expectedPath, actualPath, expectedPath);
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

static BOOL _OFCheckFilesSame(XCTestCase *self, NSString *path1, NSString *path2, BOOL requireSame, OFDiffFileOperations * _Nullable operations)
{
    __autoreleasing NSError *error = nil;

    // Collect all the files, as relative paths from the two inputs
    NSMutableSet *files1 = [NSMutableSet set];
    if (!_addRelativePaths(files1, path1, operations.pathFilter, &error)) {
        NSLog(@"Missing expected output:\n\n\tcp -r \"%@\" \"%@\"\n\n", path2, path1);
        XCTFail(@"Unable to find files at \"%@\": %@", path1, error);
        return NO;
    }
        
        
    if ([files1 count] == 0) {
        if (requireSame)
            XCTFail(@"No files at \"%@\"", path1);
        return NO;
    }
    
    NSMutableSet *files2 = [NSMutableSet set];
    if (!_addRelativePaths(files2, path2, operations.pathFilter, &error)) {
        XCTFail(@"Unable to find files at \"%@\": %@", path2, error);
        return NO;
    }
    if ([files2 count] == 0) {
        if (requireSame)
            XCTFail(@"No files at \"%@\"", path2);
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
                XCTFail(@"Error reading attributes of %@: %@", map1, error);
            return NO;
        }
        NSDictionary *attributes2 = [[NSFileManager defaultManager] attributesOfItemAtPath:map2 error:&error];
        if (!attributes2) {
            if (requireSame)
                XCTFail(@"Error reading attributes of %@: %@", map2, error);
            return NO;
        }
        
        NSString *fileType1 = [attributes1 fileType];
        NSString *fileType2 = [attributes2 fileType];
        
        if (OFNOTEQUAL(fileType1, fileType2)) {
            if (requireSame)
                XCTFail(@"One file is of type \"%@\" and the other \"%@\"", fileType1, fileType2);
            return NO;
        }
        
        if (OFISEQUAL(fileType1, NSFileTypeRegular)) {
            NSData *data1 = [[NSData alloc] initWithContentsOfFile:map1 options:0 error:&error];
            if (!data1) {
                if (requireSame)
                    XCTFail(@"Unable to read data");
                return NO;
            }
            
            NSData *data2 = [[NSData alloc] initWithContentsOfFile:map2 options:0 error:&error];
            if (!data2) {
                if (requireSame)
                    XCTFail(@"Unable to read data");
                return NO;
            }

            BOOL same = [data1 isEqual:data2];
            if (!same) {
                OFDiffFileTransformData transform = operations.transformData;
                if (transform) {
                    data1 = transform(map1, data1);
                    data2 = transform(map2, data2);
                }
                same = [data1 isEqual:data2];
            }

            if (!same) {
                // Might still mean the same thing as far as the caller is concerned.
                OFDiffFileCompareData compare = operations.compareData;
                if (compare) {
                    same = compare(map1, data1, map2, data2);
                }
            }

            if (!same) {
                if (requireSame) {
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
                    XCTFail(@"Files differ!\ndiff \"%@\" \"%@\"", map1, map2);
#else
                    OFDiffDataFiles(self, map1, map2);

                    // If we transformed the data, show the diff of the transformed value as well (which may be smaller)
                    OFDiffData(self, data1, data2);

                    XCTFail(@"Files differ!"); // This can raise if the test is set to not continue after failures.
#endif
                }
                return NO;
            }
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
                    XCTFail(@"Symlink destinations differ!\n"
                           "\"%@\" -> \"%@\"\n"
                           "\"%@\" -> \"%@\"\n", map1, destination1, map2, destination2);
                return NO;
            }
#else
            if (requireSame)
                XCTAssertEqualObjects(destination1, destination2, @"Link destinations should be the same");
#endif
        } else {
            if (requireSame)
                XCTFail(@"Don't know how to compare files of type \"%@\"", fileType1);
            return NO;
        }
    }
    
    return YES;
}

static BOOL OFCheckFilesSame(XCTestCase *self, NSString *path1, NSString *path2, BOOL requireSame, OFDiffFileOperations * _Nullable operations)
{
    OBPRECONDITION(path1);
    OBPRECONDITION(path2);
    OBPRECONDITION(OFNOTEQUAL(path1, path2), @"Why compare the file against itself?");
        
    // Use file coordination to prevent incoming edits from confusing us with partially changed file state (like an incoming rename from OmniPresence during our unit tests).
    // This can potentially hang, though, if some other code in the unit test has a file presenter that will get called and will block on the main queue somehow.
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSURL *fileURL1 = [NSURL fileURLWithPath:path1];
    NSURL *fileURL2 = [NSURL fileURLWithPath:path2];
    
    NSArray *readFileURLs = [NSArray arrayWithObjects:fileURL1, fileURL2, nil];
    __autoreleasing NSError *error = nil;
    __block NSException *raisedException = nil;
    BOOL success = [coordinator prepareToReadItemsAtURLs:readFileURLs withChanges:YES error:&error byAccessor:^BOOL(NSError **outPrepareError){
        return [coordinator readItemAtURL:fileURL1 withChanges:YES error:outPrepareError byAccessor:^BOOL(NSURL *newURL1, NSError **outRead1Error) {
            return [coordinator readItemAtURL:fileURL2 withChanges:YES error:outRead1Error byAccessor:^BOOL(NSURL *newURL2, NSError **outRead2Error) {
                @try {
                    return _OFCheckFilesSame(self, [[newURL1 absoluteURL] path], [[newURL2 absoluteURL] path], requireSame, operations);
                }
                @catch (NSException *exception) {
                    raisedException = exception;
                }
            }];
        }];
    }];

    if (raisedException)
        [raisedException raise]; // Likely a XCTAssert failure
    if (requireSame)
        XCTAssertTrue(success, @"Comparison failed: %@", [error toPropertyList]);
    return success;
}

BOOL OFSameFiles(XCTestCase *self, NSString *path1, NSString *path2, OFDiffFileOperations * _Nullable operations)
{
    return OFCheckFilesSame(self, path1, path2, NO/*requireSame*/, operations);
}


void OFDiffFiles(XCTestCase *self, NSString *path1, NSString *path2, OFDiffFileOperations * _Nullable operations)
{
    OFCheckFilesSame(self, path1, path2, YES/*requireSame*/, operations);
}

@implementation OFDiffFileOperations
@end

NS_ASSUME_NONNULL_END

