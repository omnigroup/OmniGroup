// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDAV/ODAVConformanceTest.h>

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniFoundation/NSData-OFCompression.h>
#import <OmniFoundation/OFXMLIdentifier.h>

static NSString * const rcs_id = @"$Id$";

/*
 These get run for server conformance validation as well as being hooked up as unit tests by ODAVDynamicTestCase.
 */

// Our ETag tests are off since stock Apache 2.4.x fails them. See <https://github.com/omnigroup/Apache/> for patches that make these work better. At some point we gave up on ETags though since there are no guarantees that a collection's GET-ETag is useful for tracking changes to the collection membership (PROPFIND results).
// If we really want to do collection change tracking we could look into RFC6578 (Collection sychronization), which defines both an etag-like token for collection membership, and formats for getting deep change information about a hierarchy.
#define TEST_ETAG_SUPPORT 0

NSString * const ODAVConformanceFailureErrors = @"com.omnigroup.OmniFileExchange.ConformanceFailureErrors";

static BOOL _ODAVConformanceError(NSError **outError, NSError *originalError, const char *file, unsigned line, NSString *format, ...) NS_FORMAT_FUNCTION(5,6);
static BOOL _ODAVConformanceError(NSError **outError, NSError *originalError, const char *file, unsigned line, NSString *format, ...)
{
    if (outError) {
        // Our conformance tests failed because of some unrelated error (unreachable host, authentication issue, storage space issue, etc.).  Let's just return that error, rather than bundling it up into a conformance failure error.
        // On the other hand, if there is no underlying error, then the error we are about to make *is* the root error (for example, if we are just checking if a timestamp changed).
        if (originalError && !ODAVShouldOfferToReportError(originalError)) {
            *outError = originalError;
            return NO;
        }

        NSString *description = NSLocalizedStringFromTableInBundle(@"WebDAV server failed conformance test.", @"OmniDAV", OMNI_BUNDLE, @"Error description");
        
        NSString *reason;
        if (format) {
            va_list args;
            va_start(args, format);
            reason = [[NSString alloc] initWithFormat:format arguments:args];
            va_end(args);
        } else
            reason = @"Unspecified failure.";
        
        // Override what ODAVErrorWithInfo would normally put in there (otherwise we'd get a location in this static function always).
        NSString *fileAndLine = [[NSString alloc] initWithFormat:@"%s:%d", file, line];
        ODAVErrorWithInfo(outError, ODAVServerConformanceFailed, description, reason, NSUnderlyingErrorKey, originalError,
                         OBFileNameAndNumberErrorKey, fileAndLine,
                         @"rcsid", rcs_id, nil);
    }
    return NO;
}
#define ODAVConformanceError(format, ...) _ODAVConformanceError(outError, error, __FILE__, __LINE__, format, ## __VA_ARGS__)

#define ODAVReject(x, format, ...) do { \
    if ((x)) { \
        return ODAVConformanceError(format, ## __VA_ARGS__); \
    } \
} while (0)
#define ODAVRequire(x, format, ...) ODAVReject((!(x)), format, ## __VA_ARGS__)

// Convenience macros for common setup operations that aren't really interesting
#define DAV_mkdir(d) \
    error = nil; \
    NSURL *d = [_baseURL URLByAppendingPathComponent:@ #d isDirectory:YES]; \
    ODAVRequire(d = [_connection synchronousMakeCollectionAtURL:d error:&error].URL, @"Error creating directory \"" #d "\".");

#define DAV_mkdir_at(base, d) \
    error = nil; \
    NSURL *base ## _ ## d = [base URLByAppendingPathComponent:@ #d isDirectory:YES]; \
    ODAVRequire(base ## _ ## d = [_connection synchronousMakeCollectionAtURL:base ## _ ## d error:&error].URL, @"Error creating directory \" #d \" in %@.", base);

#define DAV_write_at(base, f, data) \
    error = nil; \
    NSURL *base ## _ ## f = [base URLByAppendingPathComponent:@ #f isDirectory:NO]; \
    ODAVRequire(base ## _ ## f = [_connection synchronousPutData:data toURL:base ## _ ## f error:&error], @"Error writing file \" #f \" in %@.", base);

#define DAV_info(u) \
    error = nil; \
    ODAVFileInfo *u ## _info; \
    DAV_update_info(u);

#define DAV_update_info(u) \
    ODAVRequire(u ## _info = [_connection synchronousFileInfoAtURL:u error:&error], @"Error getting info for \"" #u "\".");

@implementation ODAVConformanceTest
{
    NSURL *_baseURL;
    NSOperationQueue *_operationQueue;
    
    NSString *_status;
    double _percentDone;
}

+ (void)eachTest:(void (^)(SEL sel, ODAVConformanceTestImp imp, ODAVConformanceTestProgress progress))applier;
{
    OBPRECONDITION(self == [ODAVConformanceTest class]); // We could iterate each superclass too if not...
    
    Method testWithErrorSentinelMethod = class_getInstanceMethod(self, @selector(_testWithErrorTypeEncodingSentinel:));
    const char *testWithErrorEncoding = method_getTypeEncoding(testWithErrorSentinelMethod);
    
    // Find all the instance methods that look like -testFoo:, taking an outError.
    unsigned int methodCount;
    Method *methods = class_copyMethodList(self, &methodCount);
    
    NSMutableArray *testMethodValues = [NSMutableArray new];
    for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
        // Make sure the method looks like what we are interested in
        Method method = methods[methodIndex];
        SEL methodSelector = method_getName(method);
        NSString *methodName = NSStringFromSelector(methodSelector);
        if (![methodName hasPrefix:@"test"])
            continue;
        if (strcmp(testWithErrorEncoding, method_getTypeEncoding(method)))
            continue;
        
        [testMethodValues addObject:[NSValue valueWithPointer:method]];
    }
    
    NSUInteger testCount = [testMethodValues count];
    [testMethodValues enumerateObjectsUsingBlock:^(NSValue *methodValue, NSUInteger testIndex, BOOL *stop) {
        Method method = [methodValue pointerValue];
        SEL methodSelector = method_getName(method);
        
        ODAVConformanceTestImp testImp = (typeof(testImp))method_getImplementation(method);
        applier(methodSelector, testImp, (ODAVConformanceTestProgress){.completed = testIndex, .total = testCount});
    }];

    if (methods) {
        free(methods);
    }
}

/*
 The unit test hooks call the test methods directly with a new file manager for each that has a base path that was just created (so the tests don't have to clean up after themselves).
 When going through -start, we update our _baseURL for each test.
*/

- initWithConnection:(ODAVConnection *)connection baseURL:(NSURL *)baseURL;
{
    OBPRECONDITION(connection);
    OBPRECONDITION(baseURL);
    
    if (!(self = [super init]))
        return nil;
    
    _operationQueue = [[NSOperationQueue alloc] init];
    _operationQueue.maxConcurrentOperationCount = 1;
    _operationQueue.name = @"com.omnigroup.OmniDAV.ODAVConformanceTest background queue";
    
    _connection = connection;
    _baseURL = baseURL;
    
    return self;
}

- (void)_finishWithError:(NSError *)error;
{
    if (_finished) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            typeof(_finished) finished = _finished; // break retain cycles
            _finished = nil;
            finished(error);
        }];
    }
}

- (void)_finishWithErrors:(NSArray *)errors;
{
    if (_finished) {
        __autoreleasing NSError *error;
        if ([errors count] > 0) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"WebDAV server failed conformance test.", @"OmniDAV", OMNI_BUNDLE, @"Error description");
            NSMutableArray *recoverySuggestions = [NSMutableArray array];
            for (NSError *anError in errors) {
                if (![anError hasUnderlyingErrorDomain:ODAVErrorDomain code:ODAVServerConformanceFailed] || !ODAVShouldOfferToReportError(anError)) {
                    // Our conformance tests failed because of some unrelated error (unreachable host, authentication issue, storage space issue, etc.).  Let's just return that error, rather than bundling it up into a conformance failure error.
                    [self _finishWithError:anError];
                    return;
                }

                // Collect all the recovery suggestions for conformance test failures
                NSString *recoverySuggestion = [anError localizedRecoverySuggestion];
                OBASSERT(recoverySuggestion != nil); // Since we're only looking at ODAVServerConformanceFailed, we should be able to rely on the recovery suggestion being set
                if (recoverySuggestion != nil) // ... but just in case it isn't, let's not crash while trying to report an error
                    [recoverySuggestions addObject:recoverySuggestion];
            }
            ODAVErrorWithInfo(&error, ODAVServerConformanceFailed, description, [recoverySuggestions componentsJoinedByString:@" "], ODAVConformanceFailureErrors, errors, nil);
        }
        [self _finishWithError:error];
    }
}

static BOOL retry(NSError **outError, BOOL (^op)(NSError **))
{
    NSUInteger triesLeft = 10;
    
    while (YES) {
        __autoreleasing NSError *tryError;
        if (op(&tryError))
            return YES;
        
        if (![tryError causedByNetworkConnectionLost] || triesLeft == 0) {
            if (outError)
                *outError = tryError;
            return NO;
        }
        
        [tryError log:@"Network connection lost -- retrying"];
        triesLeft--;
    }
}

- (void)start;
{
    [_operationQueue addOperationWithBlock:^{
        // We run each test twice, once with some spaces in the path and once without (since each case can hit different server bugs).
        NSString *testFolder = [NSString stringWithFormat:@"OmniDAV-Conformance-Tests-%@", OFXMLCreateID()]; // Users sometimes add two clients at the same time.
        NSURL *mainTestDirectory = [_baseURL URLByAppendingPathComponent:testFolder isDirectory:YES];
        NSMutableArray *errors = [NSMutableArray new];
        __autoreleasing NSError *mainError;

        // Users on high latency connections often get network connection lost errors. OmniPresence deals with these (though syncing may be slower obviously due to retried operations). We'll retry on network connection loss errors, up to a limit.
        
        // If we've tested this server before, clean up the old stuff
        {
            BOOL ok = retry(&mainError, ^BOOL(NSError **outError){
                __autoreleasing NSError *deleteError;
                if ([_connection synchronousDeleteURL:mainTestDirectory withETag:nil error:&deleteError])
                    return YES;
                if ([deleteError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND])
                    return YES;
                if (outError)
                    *outError = deleteError;
                return NO;
                
            });
            if (!ok) {
                [self _finishWithError:mainError];
                return;
            }
            
            mainError = nil;
            ok = retry(&mainError, ^BOOL(NSError **outError){
                return [_connection synchronousMakeCollectionAtURL:mainTestDirectory error:outError] != nil;
            });
            if (!ok) {
                [self _finishWithError:mainError];
                return;
            }
        }
        
        [[self class] eachTest:^(SEL sel, ODAVConformanceTestImp imp, ODAVConformanceTestProgress progress) {
            void (^runTest)(BOOL withSpace) = ^(BOOL withSpace){
                __autoreleasing NSError *perTestError;
                
                NSString *testName = [NSString stringWithFormat:@"for%@%@", NSStringFromSelector(sel), withSpace ? @" " : @"-"];
                _baseURL = [mainTestDirectory URLByAppendingPathComponent:testName isDirectory:YES];
                
                BOOL ok;
                ok = retry(&perTestError, ^BOOL(NSError **outError) {
                    return [_connection synchronousMakeCollectionAtURL:_baseURL error:outError] != nil;
                });
                if (!ok) {
                    [errors addObject:perTestError];
                    return;
                }
                
                perTestError = nil;
                
                ok = retry(&perTestError, ^BOOL(NSError **outError) {
                    return imp(self, sel, outError);
                });
                
                if (!ok) {
                    NSLog(@"Error encountered while running -%@ -- %@", NSStringFromSelector(sel), [perTestError toPropertyList]);
                    [errors addObject:perTestError];
                }
            };
            
            runTest(YES);
            [self _updatePercentDone:(2*progress.completed + 0)/(2.0*progress.total)];

            runTest(NO);
            [self _updatePercentDone:(2*progress.completed + 1)/(2.0*progress.total)];
        }];
        
        // Clean up after ourselves
        mainError = nil;
        if (![_connection synchronousDeleteURL:mainTestDirectory withETag:nil error:&mainError]) {
            [errors addObject:mainError];
        }
        
        [self _finishWithErrors:errors];
    }];
}

#pragma mark - Tests

- (BOOL)_testWithErrorTypeEncodingSentinel:(NSError **)outError;
{
    return YES;
}

#pragma mark - ETag tests

#if TEST_ETAG_SUPPORT

- (BOOL)testGetDataFailingDueToModifyingWithETagPrecondition:(NSError **)outError;
{
    [self _updateStatus:@"Testing GET with out-of-date ETag"];
    
    NSURL *file = [_baseURL URLByAppendingPathComponent:@"file"];
    
    NSError *error;
    NSData *data1 = OFRandomCreateDataOfLength(16);
    ODAVRequire([_connection synchronousPutData:data1 toURL:file error:&error], @"Error writing initial data.");
    
    // TODO: Make A DAV version of file writing return an ETag (or maybe a full file info... might not be able to get the right URL unless they return a Location header).
    ODAVFileInfo *firstFileInfo;
    ODAVRequire((firstFileInfo = [_connection synchronousFileInfoAtURL:file error:&error]), @"Error getting original file info.");
    
    // This is terrible, but it seems that Apache bases the ETag off some combination of the name, file size and modification date.
    // We just want to see that ETag-predicated GET works, here.
    NSData *data2 = OFRandomCreateDataOfLength(32);
    ODAVRequire([_connection synchronousPutData:data2 toURL:file error:&error], @"Error writing updated data.");
    
    ODAVFileInfo *secondFileInfo;
    ODAVRequire((secondFileInfo = [_connection synchronousFileInfoAtURL:file error:&error]), @"Error getting updated file info.");

    ODAVRequire(![firstFileInfo.ETag isEqual:secondFileInfo.ETag], @"Writing new content should have changed ETag.");
    
    NSData *data;
    ODAVReject((data = [_connection synchronousGetContentsOfURL:firstFileInfo.originalURL withETag:firstFileInfo.ETag error:&error]), @"ETag-predicated fetch should have failed due to mismatched ETag.");
    
    ODAVRequire([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_PRECONDITION_FAILED], @"Error should have specified precondition failure but had domain %@, code %ld.", error.domain, error.code);
    
    return YES;
}

- (BOOL)testCollectionRenameWithETagPrecondition:(NSError **)outError;
{
    [self _updateStatus:@"Testing collection MOVE with valid ETag predicate."];

    NSURL *dir1 = [_baseURL URLByAppendingPathComponent:@"dir-1" isDirectory:YES];
    NSURL *dir2 = [_baseURL URLByAppendingPathComponent:@"dir-2" isDirectory:YES];
    
    NSError *error;
    ODAVRequire(dir1 = [_fileManager createDirectoryAtURL:dir1 attributes:nil error:&error], @"Error creating first directory.");
    
    ODAVFileInfo *dirInfo;
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir1 error:&error], @"Error getting info for first directory.");
    
    ODAVRequire([_fileManager moveURL:dir1 toURL:dir2 withSourceETag:dirInfo.ETag overwrite:NO error:&error], @"Error renaming directory with valid ETag precondition.");
    
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir2 error:&error], @"Error getting info for renamed directory.");
    ODAVRequire(dirInfo.exists, @"Directory should exist at new location");
    
    return YES;
}

// Tests the source ETag hasn't changed
- (BOOL)testCollectionRenameFailingDueToETagPrecondition:(NSError **)outError;
{
    [self _updateStatus:@"Testing collection MOVE with out-of-date ETag predicate."];

    NSURL *dir1 = [_baseURL URLByAppendingPathComponent:@"dir-1" isDirectory:YES];
    NSURL *dir2 = [_baseURL URLByAppendingPathComponent:@"dir-2" isDirectory:YES];
    
    NSError *error;
    ODAVRequire(dir1 = [_fileManager createDirectoryAtURL:dir1 attributes:nil error:&error], @"Error creating first directory.");
    
    ODAVFileInfo *dirInfo;
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir1 error:&error], @"Error getting info for first directory.");
    
    // Add something to the directory to change its ETag
    ODAVRequire([_connection synchronousPutData:[NSData data] toURL:[dir1 URLByAppendingPathComponent:@"file"] error:&error], @"Error writing data to directory.");
    
    // Verify ETag changed
    ODAVFileInfo *updatedDirInfo;
    ODAVRequire(updatedDirInfo = [_connection synchronousFileInfoAtURL:dir1 error:&error], @"Error getting info of updated directory.");
    ODAVRequire(![updatedDirInfo.ETag isEqual:dirInfo.ETag], @"Directory ETag should have changed due to writing file into it.");
    
    ODAVReject([_fileManager moveURL:dir1 toURL:dir2 withSourceETag:dirInfo.ETag overwrite:NO error:&error], @"Directory rename should have failed due to ETag precondition.");
    ODAVRequire([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_PRECONDITION_FAILED], @"Error should specify precondition failure.");
    
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir2 error:&error], @"Error getting info for rename directory.");
    ODAVReject(dirInfo.exists, @"Directory should not have been renamed.");
    
    return YES;
}

// Tests the destination ETag hasn't changed (so we are replacing a known state).
- (BOOL)testCollectionReplaceWithETagPrecondition:(NSError **)outError;
{
    [self _updateStatus:@"Testing collection replacement with ETag predicate."];

    NSURL *dirA = [_baseURL URLByAppendingPathComponent:@"dir-a" isDirectory:YES];
    NSString *ETagA1;
    NSString *ETagA2;
    {
        NSError *error;
        ODAVRequire(dirA = [_fileManager createDirectoryAtURL:dirA attributes:nil error:&error], @"Error creating first directory.");
        
        // Add something to the directory to change its ETag (so it is differently from ETagB below).
        ODAVRequire([_connection synchronousPutData:[NSData data] toURL:[dirA URLByAppendingPathComponent:@"file1"] error:&error], @"Error writing data to directory.");
        
        
        ODAVFileInfo *dirInfo;
        ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dirA error:&error], @"Error getting info for directory.");
        ETagA1 = dirInfo.ETag;
        
        // Add something to the directory to change its ETag
        ODAVRequire([_connection synchronousPutData:[NSData data] toURL:[dirA URLByAppendingPathComponent:@"file2"] error:&error], @"Error writing another file to directory.");
        
        // Verify ETag changed
        ODAVFileInfo *updatedDirInfo;
        ODAVRequire(updatedDirInfo = [_connection synchronousFileInfoAtURL:dirA error:&error], @"Error getting info for updated directory.");
        ETagA2 = updatedDirInfo.ETag;
        
        ODAVRequire(![ETagA1 isEqual:ETagA2], @"Directory ETag should have changed due to writing file into it.");
    }
    
    NSURL *dirB = [_baseURL URLByAppendingPathComponent:@"dir-b" isDirectory:YES];
    NSString *ETagB;
    {
        NSError *error;
        ODAVRequire(dirB = [_fileManager createDirectoryAtURL:dirB attributes:nil error:&error], @"Error creating directory.");
        
        ODAVFileInfo *dirInfo;
        ODAVRequire (dirInfo = [_connection synchronousFileInfoAtURL:dirB error:&error], @"Error getting directory info.");
        ETagB = dirInfo.ETag;
        
        // Make sure our tests below aren't spurious
        ODAVReject([ETagA1 isEqual:ETagB], @"ETags should have differed.");
        ODAVReject([ETagA2 isEqual:ETagB], @"ETags should have differed.");
    }
    
    // Attempt with the old ETag should fail
    {
        NSError *error;
        ODAVFileInfo *dirInfo;
        
        ODAVReject([_fileManager moveURL:dirB toURL:dirA withDestinationETag:ETagA1 overwrite:YES error:&error], @"Move should have failed due to ETag precondition.");
        ODAVRequire([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_PRECONDITION_FAILED], @"Error should specify precondition failure.");
        
        error = nil;
        ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dirB error:&error], @"Error getting info for source URL.");
        ODAVRequire(dirInfo.exists, @"Source directory should still be at its original location.");
        ODAVRequire([dirInfo.ETag isEqual:ETagB], @"Source directory should still have its original ETag.");
        
        error = nil;
        ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dirA error:&error], @"Error getting info for destination URL.");
        ODAVRequire(dirInfo.exists, @"Destination directory should still exist.");
        ODAVRequire([dirInfo.ETag isEqual:ETagA2], @"Destination directory should still have the updated ETag");
    }
    
    // Attempt with the current ETag should work
    {
        NSError *error;
        ODAVFileInfo *dirInfo;
        
        ODAVRequire([_fileManager moveURL:dirB toURL:dirA withDestinationETag:ETagA2 overwrite:YES error:&error], @"Error while replacing directory.");
        
        error = nil;
        ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dirB error:&error], @"Error getting info for source URL.");
        ODAVReject(dirInfo.exists, @"Source directory should have been moved.");
        
        error = nil;
        ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dirA error:&error], @"Error getting info for destination URL.");
        ODAVRequire(dirInfo.exists, @"Destination directory should exist.");
        ODAVRequire([dirInfo.ETag isEqual:ETagB], @"Destination directory should have the new ETag.");
    }
    
    return YES;
}

- (BOOL)testCollectionCopyFailingDueToETagPrecondition:(NSError **)outError;
{
    [self _updateStatus:@"Testing collection COPY with out-of-date ETag predicate."];
    
    NSURL *dir1 = [_baseURL URLByAppendingPathComponent:@"dir-1" isDirectory:YES];
    NSURL *dir2 = [_baseURL URLByAppendingPathComponent:@"dir-2" isDirectory:YES];
    
    NSError *error;
    ODAVRequire(dir1 = [_fileManager createDirectoryAtURL:dir1 attributes:nil error:&error], @"Error creating first directory.");
    
    ODAVFileInfo *dirInfo;
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir1 error:&error], @"Error getting info for first directory.");
    
    // Add something to the directory to change its ETag
    ODAVRequire([_connection synchronousPutData:[NSData data] toURL:[dir1 URLByAppendingPathComponent:@"file"] error:&error], @"Error writing data to directory.");
    
    // Verify ETag changed
    ODAVFileInfo *updatedDirInfo;
    ODAVRequire(updatedDirInfo = [_connection synchronousFileInfoAtURL:dir1 error:&error], @"Error getting info of updated directory.");
    ODAVRequire(![updatedDirInfo.ETag isEqual:dirInfo.ETag], @"Directory ETag should have changed due to writing file into it.");
    
    ODAVReject([_connection synchronousCopyURL:dir1 toURL:dir2 withSourceETag:dirInfo.ETag overwrite:NO error:&error], @"Directory copy should have failed due to ETag precondition.");
    ODAVRequire([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_PRECONDITION_FAILED], @"Error should specify precondition failure.");
    
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir2 error:&error], @"Error getting info for destination directory.");
    ODAVReject(dirInfo.exists, @"Directory should not have been copied.");
    
    return YES;
}

- (BOOL)testCollectionCopySucceedingWithETagPrecondition:(NSError **)outError;
{
    [self _updateStatus:@"Testing collection COPY with current ETag predicate."];
    
    NSURL *dir1 = [_baseURL URLByAppendingPathComponent:@"dir-1" isDirectory:YES];
    NSURL *dir2 = [_baseURL URLByAppendingPathComponent:@"dir-2" isDirectory:YES];
    
    NSError *error;
    ODAVRequire(dir1 = [_fileManager createDirectoryAtURL:dir1 attributes:nil error:&error], @"Error creating first directory.");
    
    ODAVFileInfo *dirInfo;
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir1 error:&error], @"Error getting info for first directory.");
    
    // Add something to the directory to change its ETag
    ODAVRequire([_connection synchronousPutData:[NSData data] toURL:[dir1 URLByAppendingPathComponent:@"file"] error:&error], @"Error writing data to directory.");
    
    // Verify ETag changed
    ODAVFileInfo *updatedDirInfo;
    ODAVRequire(updatedDirInfo = [_connection synchronousFileInfoAtURL:dir1 error:&error], @"Error getting info of updated directory.");
    ODAVRequire(![updatedDirInfo.ETag isEqual:dirInfo.ETag], @"Directory ETag should have changed due to writing file into it.");
    
    ODAVRequire([_connection synchronousCopyURL:dir1 toURL:dir2 withSourceETag:updatedDirInfo.ETag overwrite:NO error:&error], @"Directory copy should succeed with ETag precondition.");
    
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir2 error:&error], @"Error getting info for copied directory.");
    ODAVRequire(dirInfo.exists, @"Directory should have been copied.");
    
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:[dir2 URLByAppendingPathComponent:@"file"] error:&error], @"Error getting copied child info");
    ODAVRequire(dirInfo.exists, @"Child file should have been copied.");

    return YES;
}

- (BOOL)testPropfindFailingDueToETagPrecondition:(NSError **)outError;
{
    [self _updateStatus:@"Testing PROPFIND with out-of-date ETag predicate."];

    NSURL *dir = [_baseURL URLByAppendingPathComponent:@"dir" isDirectory:YES];
    
    NSError *error;
    ODAVRequire(dir = [_fileManager createDirectoryAtURL:dir attributes:nil error:&error], @"Error creating directory.");
    
    ODAVFileInfo *dirInfo;
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir error:&error], @"Error getting directory info.");
    
    // Add something to the directory to change its ETag
    ODAVRequire([_connection synchronousPutData:[NSData data] toURL:[dir URLByAppendingPathComponent:@"file"] error:&error], @"Error writing file to directory.");
    
    // Verify ETag changed
    ODAVFileInfo *updatedDirInfo;
    ODAVRequire (updatedDirInfo = [_connection synchronousFileInfoAtURL:dir error:&error], @"Error getting updated info for directory.");
    ODAVReject([updatedDirInfo.ETag isEqual:dirInfo.ETag], @"Directory ETag should have changed due to writing file into it.");
    
    NSArray *fileInfos;
    ODAVReject(fileInfos = [_fileManager directoryContentsAtURL:dir withETag:dirInfo.ETag collectingRedirects:nil options:OFSDirectoryEnumerationSkipsSubdirectoryDescendants|OFSDirectoryEnumerationSkipsHiddenFiles serverDate:NULL error:&error], @"Expected error getting info for directory with old ETag.");
    ODAVRequire([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_PRECONDITION_FAILED], @"Error should specify precondition failure.");
    
    return YES;
}

- (BOOL)testDeleteWithETag:(NSError **)outError;
{
    [self _updateStatus:@"Testing deletion with ETag predicate."];
    
    NSURL *dir = [_baseURL URLByAppendingPathComponent:@"dir" isDirectory:YES];
    
    NSError *error;
    ODAVRequire(dir = [_fileManager createDirectoryAtURL:dir attributes:nil error:&error], @"Error creating directory.");
    
    ODAVFileInfo *fileInfo;
    ODAVRequire(fileInfo = [_connection synchronousFileInfoAtURL:dir error:&error], @"Error getting info for directory.");
    
    // Add something to the directory to change its ETag
    ODAVRequire([_connection synchronousPutData:[NSData data] toURL:[dir URLByAppendingPathComponent:@"file"] error:&error], @"Error writing file to directory.");
    
    ODAVReject([_fileManager deleteURL:dir withETag:fileInfo.ETag error:&error], @"Delete with the old ETag should fail");
    
    ODAVRequire(fileInfo = [_connection synchronousFileInfoAtURL:dir error:&error], @"Error getting updated info for directory.");
    ODAVRequire([_fileManager deleteURL:dir withETag:fileInfo.ETag error:&error], @"Delete with the new ETag should succeed.");
    
    return YES;
}

#endif

// This is slow, but we'd like to have some confidence that the ETag of a directory reliably changes when new files are added.
// (This fails because a directory doesn't have an ETag, only GET-resources have ETags. See RFC2518[8.4]: "[It] is possible that the result of a GET on a collection will bear no correlation to the membership of the collection.")
#if 0
- (BOOL)testCollectionETagDistributionVsAddMultipleFiles:(NSError **)outError;
{
    [self _updateStatus:@"Testing ETag distribution when adding multiple files."];

    NSURL *dir = [_baseURL URLByAppendingPathComponent:@"dir" isDirectory:YES];
    
    NSError *error;
    ODAVRequire(dir = [_fileManager createDirectoryAtURL:dir attributes:nil error:&error], @"Error creating directory.");
    
    NSMutableSet *seenETags = [NSMutableSet new];
    
    ODAVFileInfo *dirInfo;
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir error:&error], @"Error getting info for directory.");
    [seenETags addObject:dirInfo.ETag];
    
    for (NSUInteger fileIndex = 0; fileIndex < 1000; fileIndex++) {
        NSURL *file = [dir URLByAppendingPathComponent:[NSString stringWithFormat:@"file%ld", fileIndex]];
        ODAVRequire([_connection synchronousPutData:[NSData data] toURL:file error:&error], @"Error writing file to directory.");
        
        ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir error:&error], @"Error getting updated info for directory.");
        
        ODAVReject([seenETags member:dirInfo.ETag], @"should not repeat ETags");
        [seenETags addObject:dirInfo.ETag];
    }
    //NSLog(@"%ld seenETags = %@", [seenETags count], seenETags);
    
    return YES;
}
#endif

#if 0 // Fails; Apache seems to base the ETag off some combination of the file length, name, and contents length.
- (BOOL)testFileETagDistributionVsModifyContents:(NSError **)outError;
{
    [self _updateStatus:@"Testing file ETag distribution when modifying its contents."];
    
    NSError *error;

    NSURL *file = [_baseURL URLByAppendingPathComponent:@"file" isDirectory:NO];
        
    NSMutableSet *seenETags = [NSMutableSet new];

    for (NSUInteger fileIndex = 0; fileIndex < 1000; fileIndex++) {
        ODAVRequire([_connection synchronousPutData:OFRandomCreateDataOfLength(16) toURL:file error:&error], @"Error writing file.");
        
        ODAVFileInfo *fileInfo;
        ODAVRequire(fileInfo = [_connection synchronousFileInfoAtURL:file error:&error], @"Error getting info for file.");
        
        if ([seenETags member:fileInfo.ETag])
            NSLog(@"Duplicate ETag \"%@\"", fileInfo.ETag);
        [seenETags addObject:fileInfo.ETag];
    }
    NSLog(@"%ld seenETags", [seenETags count]);
    ODAVRequire([seenETags count] == 1000, @"ETag repeated.");

    return YES;
}
#endif

#if 0 // Fails; the directory ETag covers only 8 values for 1000 modifications
- (BOOL)testCollectionETagDistributionVsModifyFile:(NSError **)outError;
{
    [self _updateStatus:@"Testing collection ETag distribution when modifying a single contained file."];

    NSURL *dir = [_baseURL URLByAppendingPathComponent:@"dir" isDirectory:YES];
    
    NSError *error;
    ODAVRequire(dir = [_fileManager createDirectoryAtURL:dir attributes:nil error:&error], @"Error creating directory.");
    
    NSMutableSet *seenETags = [NSMutableSet new];
    
    ODAVFileInfo *dirInfo;
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir error:&error], @"Error getting info for directory.");
    [seenETags addObject:dirInfo.ETag];
    
    OFRandomState *state = OFRandomStateCreate();
    
    NSURL *file = [dir URLByAppendingPathComponent:@"file"];
    
    for (NSUInteger fileIndex = 0; fileIndex < 1000; fileIndex++) {
        NSUInteger fileLength = OFRandomNextState64(state) % 1024;
        ODAVRequire([_connection synchronousPutData:[NSData randomDataOfLength:fileLength] toURL:file error:&error], @"Error writing file to directory.");
        
        ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir error:&error], @"Error getting updated info for directory.");
        
        ODAVReject([seenETags member:dirInfo.ETag], @"ETag repeated.");
        [seenETags addObject:dirInfo.ETag];
    }
    NSLog(@"%ld seenETags = %@", [seenETags count], seenETags);
    
    OFRandomStateDestroy(state);
    
    return YES;
}
#endif

#if 0 // This fails (we only end up with 9 distinct ETags for 1000 add/removes). I'd expect if it was going to repeat, it would just toggle back and forth between two tags...
- (BOOL)testCollectionETagDistributionVsAddRemoveSingleFile:(NSError **)outError;
{
    [self _updateStatus:@"Testing ETag distribution when adding and removing a single file."];

    NSURL *dir = [_baseURL URLByAppendingPathComponent:@"dir" isDirectory:YES];
    
    NSError *error;
    ODAVRequire(dir = [_fileManager createDirectoryAtURL:dir attributes:nil error:&error], @"Error creating directory.");
    
    NSMutableSet *seenETags = [NSMutableSet new];
    
    ODAVFileInfo *dirInfo;
    ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir error:&error], @"Error getting info for directory.");
    [seenETags addObject:dirInfo.ETag];
    
    NSURL *file = [dir URLByAppendingPathComponent:@"file"];
    
    for (NSUInteger fileIndex = 0; fileIndex < 1000; fileIndex++) {
        ODAVRequire([_connection synchronousPutData:[NSData data] toURL:file error:&error], @"Error writing file to directory.");
        
        ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir error:&error], @"Error getting updated info for directory.");
        [seenETags addObject:dirInfo.ETag];
        
        ODAVRequire([_fileManager deleteURL:file error:&error], @"Error deleting file.");
        
        ODAVRequire(dirInfo = [_connection synchronousFileInfoAtURL:dir error:&error], @"Error getting updated info for directory.");
        
        [seenETags addObject:dirInfo.ETag];
        ODAVReject([seenETags member:dirInfo.ETag], @"ETag repeated.");
    }
    
    //NSLog(@"%ld seenETags = %@", [seenETags count], seenETags);
    return YES;
}
#endif

#pragma mark - Other tests

// Replacing a child of a collection isn't guaranteed to update the ETag of the collection, but it must update the date modified.
- (BOOL)testReplacedCollectionUpdatesModificationDate:(NSError **)outError;
{
    __autoreleasing NSError *error;
    
    // Make a 'document'
    DAV_mkdir(parent);
    DAV_mkdir_at(parent, tmp);
    DAV_mkdir_at(parent, doc);
    DAV_write_at(parent_doc, contents, OFRandomCreateDataOfLength(16));
    
    // Get the version of the parent at this point, and the original document
    DAV_info(parent);
    DAV_info(parent_doc);
    
    // Make a replacement document in the temporary directory
    DAV_mkdir_at(parent_tmp, doc);
    DAV_write_at(parent_tmp_doc, contents, OFRandomCreateDataOfLength(16));
    
    sleep(1); // Server times have 1s resolution
    
    // Replace the original document
    ODAVRequire([_connection synchronousMoveURL:parent_tmp_doc toURL:parent_doc withDestinationETag:parent_doc_info.ETag overwrite:YES error:&error], @"Should be able to move a file over an existing file when overwrite is enabled.");

    // Check that the modification date of the parent has changed.
    NSDate *originalDate = parent_info.lastModifiedDate;
    DAV_update_info(parent);
    ODAVRequire(OFNOTEQUAL(originalDate, parent_info.lastModifiedDate), @"When a file is moved into a directory and replaces another file, the directory's modification date should change.");
    
    return YES;
}

- (BOOL)testServerDateMovesForward:(NSError **)outError;
{
    __autoreleasing NSError *error;
    
    DAV_mkdir(dir);
    
    ODAVFileInfo *info;
    __autoreleasing NSDate *originalDate;
    ODAVRequire(info = [_connection synchronousFileInfoAtURL:dir serverDate:&originalDate error:&error], @"Error getting directory info.");
    ODAVRequire(originalDate, @"Server responses should include a Date header with the server's date and time.");
    
    sleep(1);
    
    __autoreleasing NSDate *laterDate;
    ODAVRequire(info = [_connection synchronousFileInfoAtURL:dir serverDate:&laterDate error:&error], @"Error getting directory info.");
    
    ODAVRequire(laterDate, @"Server responses should include a Date header with the server's date and time.");
    ODAVRequire([laterDate isAfterDate:originalDate], @"The date returned by a server's Date header should move forward every second.");

    return YES;
}

- (BOOL)testCopyFileReturnsDestinationURL:(NSError **)outError;
{    
    __autoreleasing NSError *error;
    
    DAV_mkdir(a);
    NSURL *b = [_baseURL URLByAppendingPathComponent:@"b" isDirectory:NO];
    
    NSURL *dest = [_connection synchronousCopyURL:a toURL:b withSourceETag:nil overwrite:NO error:&error];
    ODAVRequire(dest, @"Copy of file should succeed");

    // Have to allow redirection -- we mostly want to make sure we don't get the original URL back.
    ODAVRequire([[dest path] isEqual:[b path]], @"Copy of file should return the correct destination URL.");
    
    return YES;
}

- (BOOL)testCopyCollectionReturnsDestinationURL:(NSError **)outError;
{    
    __autoreleasing NSError *error;
    
    DAV_mkdir(a);
    NSURL *b = [_baseURL URLByAppendingPathComponent:@"b" isDirectory:YES];
    
    NSURL *dest = [_connection synchronousCopyURL:a toURL:b withSourceETag:nil overwrite:NO error:&error];
    ODAVRequire(dest, @"Copy of collection should succeed");
    
    // Have to allow redirection -- we mostly want to make sure we don't get the original URL back.
    ODAVRequire([[dest path] isEqual:[b path]], @"Copy of collection should return the correct destination URL.");
    
    return YES;
}

- (BOOL)testMoveFileReturnsDestinationURL:(NSError **)outError;
{
    NSURL *main = _baseURL;
    
    __autoreleasing NSError *error;
    DAV_write_at(main, a, [NSData data]);
    NSURL *main_b = [main URLByAppendingPathComponent:@"b" isDirectory:NO];
    
    NSURL *dest = [_connection synchronousMoveURL:main_a toMissingURL:main_b error:&error];
    ODAVRequire(dest, @"Move of file should succeed");
    
    // Have to allow redirection -- we mostly want to make sure we don't get the original URL back.
    ODAVRequire([[dest path] isEqual:[main_b path]], @"Move of file should return the correct destination URL.");
    
    return YES;
}

- (BOOL)testMoveCollectionReturnsDestinationURL:(NSError **)outError;
{
    NSURL *main = _baseURL;
    
    __autoreleasing NSError *error;
    DAV_write_at(main, a, [NSData data]);
    NSURL *main_b = [main URLByAppendingPathComponent:@"b" isDirectory:YES];
    
    NSURL *dest = [_connection synchronousMoveURL:main_a toMissingURL:main_b error:&error];
    ODAVRequire(dest, @"Move of collection should succeed");

    // Have to allow redirection -- we mostly want to make sure we don't get the original URL back.
    ODAVRequire([[dest path] isEqual:[main_b path]], @"Move of collection should return the correct destination URL.");
    
    return YES;
}

- (BOOL)testMoveFileIfMissing:(NSError **)outError;
{
    NSURL *main = _baseURL;
    
    __autoreleasing NSError *error;
    DAV_write_at(main, a, [NSData data]);
    DAV_write_at(main, b, [NSData data]);
    
    NSURL *main_c = [main URLByAppendingPathComponent:@"c" isDirectory:NO];
    
    ODAVRequire([_connection synchronousMoveURL:main_a toMissingURL:main_c error:&error], @"Move without overwrite should succeed when moving a plain file to an empty location.");
    ODAVReject([_connection synchronousMoveURL:main_b toMissingURL:main_c error:&error], @"Move without overwrite should fail when moving a plain file to a location that is already in use.");
    
    ODAVRequire([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_PRECONDITION_FAILED], @"Moving a file to a location which already exists should return a precondition error (%d) rather than an error in domain %@ with code %ld.", ODAV_HTTP_PRECONDITION_FAILED, error.domain, error.code);
    
    return YES;
}

- (BOOL)testMoveCollectionIfMissing:(NSError **)outError;
{
    NSURL *main = _baseURL;
    
    __autoreleasing NSError *error;
    DAV_mkdir(a);
    DAV_mkdir(b);
    
    NSURL *c = [main URLByAppendingPathComponent:@"c" isDirectory:YES];
    
    ODAVRequire([_connection synchronousMoveURL:a toMissingURL:c error:&error], @"Move without overwrite should succeed when moving a directory to an empty location.");
    ODAVReject([_connection synchronousMoveURL:b toMissingURL:c error:&error], @"Move without overwrite should fail when moving a directory to a location that is already in use.");
    
    ODAVRequire([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_PRECONDITION_FAILED], @"Moving a directory to a location which already exists should return a precondition error (%d) rather than an error in domain %@ with code %ld.", ODAV_HTTP_PRECONDITION_FAILED, error.domain, error.code);
    
    return YES;
}

- (BOOL)testMoveFileToDeeplyMissingCollection:(NSError **)outError;
{
    NSURL *main = _baseURL;
    __autoreleasing NSError *error;
    
    DAV_write_at(main, a, [NSData data]);
    
    NSURL *dirB = [main URLByAppendingPathComponent:@"b" isDirectory:YES];
    NSURL *destB = [dirB URLByAppendingPathComponent:@"file" isDirectory:NO];
    
    NSURL *dirC = [dirB URLByAppendingPathComponent:@"c" isDirectory:YES];
    NSURL *destC = [dirC URLByAppendingPathComponent:@"file" isDirectory:NO];
    
    // Apache returns ODAV_HTTP_INTERNAL_SERVER_ERROR for both these ><
    ODAVReject([_connection synchronousMoveURL:main_a toMissingURL:destB error:&error], @"Should not be able to move a file inside a missing collection.");
    ODAVReject([_connection synchronousMoveURL:main_a toMissingURL:destC error:&error], @"Should not be able to move a file inside a deeply missing collection.");
    
    return YES;
}

- (BOOL)testMoveCollectionToDeeplyMissingCollection:(NSError **)outError;
{
    NSURL *main = _baseURL;
    __autoreleasing NSError *error;
    
    DAV_mkdir(a);
    
    NSURL *dirB = [main URLByAppendingPathComponent:@"b" isDirectory:YES];
    NSURL *destB = [dirB URLByAppendingPathComponent:@"dir" isDirectory:YES];
    
    NSURL *dirC = [dirB URLByAppendingPathComponent:@"c" isDirectory:YES];
    NSURL *destC = [dirC URLByAppendingPathComponent:@"dir" isDirectory:YES];
    
    // Apache returns ODAV_HTTP_INTERNAL_SERVER_ERROR for both these ><
    ODAVReject([_connection synchronousMoveURL:a toMissingURL:destB error:&error], @"Should not be able to move a collection inside a missing collection.");
    ODAVReject([_connection synchronousMoveURL:a toMissingURL:destC error:&error], @"Should not be able to move a collection inside a deeply missing collection.");
    
    return YES;
}

// <bug:///87588> (Some Apache configurations return headers such that NSURLConnection decompresses gzip data)
// This can be caused by this Apache module writing headers so that NSURLConnection decides it should decompress the gzip data.
//
//   LoadModule mime_magic_module libexec/apache2/mod_mime_magic.so
//
- (BOOL)testDownloadingCompressedDataStaysCompressed:(NSError **)outError;
{
    __autoreleasing NSError *error;
    NSData *xmlData = [@"<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"no\"?>\n<!DOCTYPE outline PUBLIC \"-//omnigroup.com//DTD OUTLINE 3.0//EN\" \"http://www.omnigroup.com/namespace/OmniOutliner/xmloutline-v3.dtd\">" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSData *compressedData;
    ODAVRequire(compressedData = [xmlData compressedData:&error], @"[Internal error: data compression should succeed.]");;
    
    NSURL *main = _baseURL;
    DAV_write_at(main, file, compressedData);
    
    NSData *readData;
    ODAVRequire((readData = [_connection synchronousGetContentsOfURL:main_file ETag:nil error:&error]), @"Fetch of compressed data should work.");
    ODAVRequire([compressedData isEqualToData:readData], @"Server should not automatically assign a compressed MIME type, because it triggers automatic decompression when the file is retrieved.");
    
    return YES;
}

// This doesn't work in Apache. They only validate the If headers vs a small set of resources, not including those only mentioned in the If headers. To me the spec says they should, but fixing this is likely to be hard enough that we'll just avoid using it: "Additionally, the mere fact that a state token appears in an If header means that it has been "submitted" with the request. In general, this is used to indicate that the client has knowledge of that state token. The semantics for submitting a state token depend on its type (for lock tokens, please refer to Section 6).
// [wiml]: The behavior is described in sec. 9.4.2 of rfc2518. In specific, the example 9.4.2.1 has an example of using the tagged-list format, mentioning a random third resource, and saying that that part of the If: header should have no effect. This is obviously not the most useful semantics for If: to have, but it is clearly part of the spec.
#if 0
// <http://www.webdav.org/specs/rfc4918.html#rfc.section.10.4> "The If request header is intended to have similar functionality to the If-Match header defined in Section 14.24 of [RFC2616]"
// <http://tools.ietf.org/html/rfc2616#section-14.24> "or if "*" is given and any current entity exists for that resource, then the server MAY perform the requested method as if the If-Match header field did not exist."
- (BOOL)testReplaceCollectionIfContainsGivenFile:(NSError **)outError;
{
    __autoreleasing NSError *error;

    // Make sure we have URL encoded characters
    NSURL *src = [_baseURL URLByAppendingPathComponent:@"src dir" isDirectory:YES];
    ODAVRequire(src = [_fileManager createDirectoryAtURL:src attributes:nil error:&error], @"Error creating source directory.");
    NSURL *dst = [_baseURL URLByAppendingPathComponent:@"dst dir" isDirectory:YES];
    ODAVRequire(dst = [_fileManager createDirectoryAtURL:dst attributes:nil error:&error], @"Error creating destination directory.");

    NSURL *dst_tag_missing = [dst URLByAppendingPathComponent:@"tag file" isDirectory:NO];
    ODAVReject([_fileManager moveURL:src toURL:dst ifURLExists:dst_tag_missing error:&error], @"dst/tag is missing, so this should fail");
    
    DAV_write_at(dst, tag, [NSData data]);
    ODAVRequire([_fileManager moveURL:src toURL:dst ifURLExists:dst_tag_missing error:&error], @"dst/tag is now present, so this should work");
    
    return YES;
}
#endif

// Support for testing the failure path.
- (BOOL)testFail:(NSError **)outError;
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ODAVConformanceTestFailIntentionally"]) {
        __autoreleasing NSError *error;
        ODAVRequire(NO, @"Failing intentionally to test failure path because ODAVConformanceTestFailIntentionally is set.");
    }
    
    return YES;
}

#pragma mark - Private

- (void)_updateStatus:(NSString *)status;
{
    _status = [status copy];
    
    if (_statusChanged) {
        double percentDone = _percentDone;
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            _statusChanged(status, percentDone);
        }];
    }
}

- (void)_updatePercentDone:(double)percentDone;
{
    _percentDone = percentDone;
    if (_statusChanged) {
        NSString *status = _status;
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            _statusChanged(status, percentDone);
        }];
    }
}

@end
