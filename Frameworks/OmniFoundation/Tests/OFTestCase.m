// Copyright 2008, 2010-2011 Omni Development, Inc. All rights reserved.
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
    NSString *casesPath;
    NSDictionary *allTestCases;
    NSEnumerator *methodEnumerator;
    NSString *methodName;
    SenTestSuite *suite;
    
    casesPath = [[NSBundle bundleForClass:self] pathForResource:[self description] ofType:@"tests"];
    allTestCases = [NSDictionary dictionaryWithContentsOfFile:casesPath];
    if (!allTestCases) {
        [NSException raise:NSGenericException format:@"Unable to load test cases for class %@ from path: \"%@\"", [self description], casesPath];
        return nil;
    }
    
    suite = [[SenTestSuite alloc] initWithName:[casesPath lastPathComponent]];
    [suite autorelease];
    
    methodEnumerator = [allTestCases keyEnumerator];
    while( (methodName = [methodEnumerator nextObject]) != nil ) {
        [suite addTest:[self testSuiteForMethod:methodName cases:[allTestCases objectForKey:methodName]]];
    }
    
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
    
    SenTestSuite *suite = [[[SenTestSuite alloc] initWithName:suiteName] autorelease];
    
    for (id testArguments in testCases) {
        NSInvocation *testInvocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        [testInvocation setSelector:testSelector];
        [testInvocation setArgument:&testArguments atIndex:2];
        [testInvocation retainArguments];
        
        OFTestCase *testCase = [self testCaseWithInvocation:testInvocation];
        [suite addTest:testCase];
    }
    
    return suite;
} 

@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <OmniBase/NSError-OBExtensions.h>

void OFDiffData(SenTestCase *testCase, NSData *expected, NSData *actual)
{
    NSString *name = [testCase name];
    
    NSError *error = nil;
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

void OFDiffFiles(SenTestCase *self, NSString *path1, NSString *path2, OFDiffFilesPathFilter pathFilter)
{
    OBPRECONDITION(path1);
    OBPRECONDITION(path2);
    
    NSError *error = nil;
    
    // Collect all the files, as relative paths from the two inputs
    NSMutableSet *files1 = [NSMutableSet set];
    OBShouldNotError(_addRelativePaths(files1, path1, pathFilter, &error));
    if ([files1 count] == 0) {
        STFail(@"No files at \"%@\"", path1);
        return;
    }
    
    NSMutableSet *files2 = [NSMutableSet set];
    OBShouldNotError(_addRelativePaths(files2, path2, pathFilter, &error));
    if ([files2 count] == 0) {
        STFail(@"No files at \"%@\"", path2);
        return;
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
        
        NSDictionary *attributes1;
        NSDictionary *attributes2;
        OBShouldNotError((attributes1 = [[NSFileManager defaultManager] attributesOfItemAtPath:map1 error:&error]));
        OBShouldNotError((attributes2 = [[NSFileManager defaultManager] attributesOfItemAtPath:map1 error:&error]));

        NSString *fileType1 = [attributes1 fileType];
        NSString *fileType2 = [attributes2 fileType];
        
        if (OFNOTEQUAL(fileType1, fileType2)) {
            STFail(@"One file is of type \"%@\" and the other \"%@\"", fileType1, fileType2);
            return;
        }

        if (OFISEQUAL(fileType1, NSFileTypeRegular)) {
            NSData *data1, *data2;
            OBShouldNotError((data1 = [[NSData alloc] initWithContentsOfFile:map1 options:0 error:&error]));
            OBShouldNotError((data2 = [[NSData alloc] initWithContentsOfFile:map2 options:0 error:&error]));
        
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
            if (OFNOTEQUAL(data1, data2))
                STFail(@"Files differ!\ndiff \"%@\" \"%@\"", map1, map2);
#else
            OFDataShouldBeEqual(data1, data2);
#endif
            
            [data1 release];
            [data2 release];
        } else if (OFISEQUAL(fileType1, NSFileTypeDirectory)) {
            // could maybe compare attributes...
        } else {
            STFail(@"Don't know how to compare files of type \"%@\"", fileType1);
            return;
        }
    }
}

