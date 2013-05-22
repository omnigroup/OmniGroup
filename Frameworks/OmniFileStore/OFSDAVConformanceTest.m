// Copyright 2008-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDAVConformanceTest.h>

#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniFoundation/NSData-OFCompression.h>

static NSString * const rcs_id = @"$Id$";

/*
 These get run for server conformance validation as well as being hooked up as unit tests by OFSDAVDynamicTestCase.
 */

// Our ETag tests are off since stock Apache 2.4.x fails them. See <https://github.com/omnigroup/Apache/> for patches that make these work better. At some point we gave up on ETags though since there are no guarantees about what will make them change.
#define TEST_ETAG_SUPPORT 0

NSString * const OFSDAVConformanceFailureErrors = @"com.omnigroup.OmniFileExchange.ConformanceFailureErrors";

static BOOL _OFSDAVConformanceError(NSError **outError, NSError *originalError, const char *file, unsigned line, NSString *format, ...) NS_FORMAT_FUNCTION(5,6);
static BOOL _OFSDAVConformanceError(NSError **outError, NSError *originalError, const char *file, unsigned line, NSString *format, ...)
{
    if (outError) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"WebDAV server failed conformance test.", @"OmniFileStore", OMNI_BUNDLE, @"Error description");
        
        NSString *reason;
        if (format) {
            va_list args;
            va_start(args, format);
            reason = [[NSString alloc] initWithFormat:format arguments:args];
            va_end(args);
        } else
            reason = @"Unspecified failure.";
        
        // Override what OFSErrorWithInfo would normally put in there (otherwise we'd get a location in this static function always).
        NSString *fileAndLine = [[NSString alloc] initWithFormat:@"%s:%d", file, line];
        OFSErrorWithInfo(outError, OFSDAVFileManagerConformanceFailed, description, reason, NSUnderlyingErrorKey, originalError,
                         OBFileNameAndNumberErrorKey, fileAndLine,
                         @"rcsid", rcs_id, nil);
    }
    return NO;
}
#define OFSDAVConformanceError(format, ...) _OFSDAVConformanceError(outError, error, __FILE__, __LINE__, format, ## __VA_ARGS__)

#define OFSDAVReject(x, format, ...) do { \
    if ((x)) { \
        return OFSDAVConformanceError(format, ## __VA_ARGS__); \
    } \
} while (0)
#define OFSDAVRequire(x, format, ...) OFSDAVReject((!(x)), format, ## __VA_ARGS__)

// Convenience macros for common setup operations that aren't really interesting
#define DAV_mkdir(d) \
    error = nil; \
    NSURL *d = [_baseURL URLByAppendingPathComponent:@ #d isDirectory:YES]; \
    OFSDAVRequire(d = [_fileManager createDirectoryAtURL:d attributes:nil error:&error], @"Error creating directory \"" #d "\".");

#define DAV_mkdir_at(base, d) \
    error = nil; \
    NSURL *base ## _ ## d = [base URLByAppendingPathComponent:@ #d isDirectory:YES]; \
    OFSDAVRequire(base ## _ ## d = [_fileManager createDirectoryAtURL:base ## _ ## d attributes:nil error:&error], @"Error creating directory \" #d \" in %@.", base);

#define DAV_write_at(base, f, data) \
    error = nil; \
    NSURL *base ## _ ## f = [base URLByAppendingPathComponent:@ #f isDirectory:NO]; \
    OFSDAVRequire(base ## _ ## f = [_fileManager writeData:data toURL:base ## _ ## f atomically:NO error:&error], @"Error writing file \" #f \" in %@.", base);

#define DAV_info(u) \
    error = nil; \
    OFSFileInfo *u ## _info; \
    DAV_update_info(u);

#define DAV_update_info(u) \
    OFSDAVRequire(u ## _info = [_fileManager fileInfoAtURL:u error:&error], @"Error getting info for \"" #u "\".");

@implementation OFSDAVConformanceTest
{
    NSURL *_baseURL;
    NSOperationQueue *_operationQueue;
}

+ (void)eachTest:(void (^)(SEL sel, OFSDAVConformanceTestImp imp))applier;
{
    OBPRECONDITION(self == [OFSDAVConformanceTest class]); // We could iterate each superclass too if not...
    
    Method testWithErrorSentinelMethod = class_getInstanceMethod(self, @selector(_testWithErrorTypeEncodingSentinel:));
    const char *testWithErrorEncoding = method_getTypeEncoding(testWithErrorSentinelMethod);
    
    // Find all the instance methods that look like -testFoo:, taking an outError.
    unsigned int methodCount;
    Method *methods = class_copyMethodList(self, &methodCount);
    
    for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
        // Make sure the method looks like what we are interested in
        Method method = methods[methodIndex];
        SEL methodSelector = method_getName(method);
        NSString *methodName = NSStringFromSelector(methodSelector);
        if (![methodName hasPrefix:@"test"])
            continue;
        if (strcmp(testWithErrorEncoding, method_getTypeEncoding(method)))
            continue;
        
        OFSDAVConformanceTestImp testImp = (typeof(testImp))method_getImplementation(method);

        applier(methodSelector, testImp);
    }
}

/*
 The unit test hooks call the test methods directly with a new file manager for each that has a base path that was just created (so the tests don't have to clean up after themselves).
 When going through -start, we update our _baseURL for each test.
*/

- initWithFileManager:(OFSDAVFileManager *)fileManager;
{
    OBPRECONDITION(fileManager);
    
    if (!(self = [super init]))
        return nil;
    
    _operationQueue = [[NSOperationQueue alloc] init];
    _operationQueue.maxConcurrentOperationCount = 1;
    _operationQueue.name = @"com.omnigroup.OmniFileStore.OFSDAVConformanceTest background queue";
    
    _fileManager = fileManager;
    _baseURL = fileManager.baseURL;
    
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
            NSString *description = NSLocalizedStringFromTableInBundle(@"WebDAV server failed conformance test.", @"OmniFileStore", OMNI_BUNDLE, @"Error description");
            NSArray *recoverySuggestions = [errors arrayByPerformingBlock:^(NSError *anError) {
                return [anError localizedRecoverySuggestion];
            }];
            OFSErrorWithInfo(&error, OFSDAVFileManagerConformanceFailed, description, [recoverySuggestions componentsJoinedByString:@" "], OFSDAVConformanceFailureErrors, errors, nil);
        }
        [self _finishWithError:error];
    }
}

- (void)start;
{
    [_operationQueue addOperationWithBlock:^{
        // Put spaces in the path to make sure we run tests that force URL encoding
        NSURL *mainTestDirectory = [_baseURL URLByAppendingPathComponent:@"OmniFileStore DAV Conformance Tests" isDirectory:YES];
        NSMutableArray *errors = [NSMutableArray new];
        __autoreleasing NSError *mainError;

        // If we've tested this server before, clean up the old stuff
        if (![_fileManager deleteURL:mainTestDirectory error:&mainError]) {
            if (![mainError hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_NOT_FOUND]) {
                [self _finishWithError:mainError];
                return;
            }
        }

        mainError = nil;
        if (![_fileManager createDirectoryAtURL:mainTestDirectory attributes:nil error:&mainError]) {
            [self _finishWithError:mainError];
            return;
        }
        
        [[self class] eachTest:^(SEL sel, OFSDAVConformanceTestImp imp) {
            __autoreleasing NSError *perTestError;

            _baseURL = [mainTestDirectory URLByAppendingPathComponent:NSStringFromSelector(sel) isDirectory:YES];
            if (![_fileManager createDirectoryAtURL:_baseURL attributes:nil error:&perTestError]) {
                [errors addObject:perTestError];
                return;
            }

            perTestError = nil;
            if (!imp(self, sel, &perTestError)) {
                NSLog(@"Error encountered while running -%@ -- %@", NSStringFromSelector(sel), [perTestError toPropertyList]);
                [errors addObject:perTestError];
            }
        }];
        
        // Clean up after ourselves
        mainError = nil;
        if (![_fileManager deleteURL:mainTestDirectory error:&mainError]) {
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
    OFSDAVRequire([_fileManager writeData:data1 toURL:file atomically:NO error:&error], @"Error writing initial data.");
    
    // TODO: Make A DAV version of file writing return an ETag (or maybe a full file info... might not be able to get the right URL unless they return a Location header).
    OFSFileInfo *firstFileInfo;
    OFSDAVRequire((firstFileInfo = [_fileManager fileInfoAtURL:file error:&error]), @"Error getting original file info.");
    
    // This is terrible, but it seems that Apache bases the ETag off some combination of the name, file size and modification date.
    // We just want to see that ETag-predicated GET works, here.
    NSData *data2 = OFRandomCreateDataOfLength(32);
    OFSDAVRequire([_fileManager writeData:data2 toURL:file atomically:NO error:&error], @"Error writing updated data.");
    
    OFSFileInfo *secondFileInfo;
    OFSDAVRequire((secondFileInfo = [_fileManager fileInfoAtURL:file error:&error]), @"Error getting updated file info.");

    OFSDAVRequire(![firstFileInfo.ETag isEqual:secondFileInfo.ETag], @"Writing new content should have changed ETag.");
    
    NSData *data;
    OFSDAVReject((data = [_fileManager dataWithContentsOfURL:firstFileInfo.originalURL withETag:firstFileInfo.ETag error:&error]), @"ETag-predicated fetch should have failed due to mismatched ETag.");
    
    OFSDAVRequire([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_PRECONDITION_FAILED], @"Error should have specified precondition failure but had domain %@, code %ld.", error.domain, error.code);
    
    return YES;
}

- (BOOL)testCollectionRenameWithETagPrecondition:(NSError **)outError;
{
    [self _updateStatus:@"Testing collection MOVE with valid ETag predicate."];

    NSURL *dir1 = [_baseURL URLByAppendingPathComponent:@"dir-1" isDirectory:YES];
    NSURL *dir2 = [_baseURL URLByAppendingPathComponent:@"dir-2" isDirectory:YES];
    
    NSError *error;
    OFSDAVRequire(dir1 = [_fileManager createDirectoryAtURL:dir1 attributes:nil error:&error], @"Error creating first directory.");
    
    OFSFileInfo *dirInfo;
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir1 error:&error], @"Error getting info for first directory.");
    
    OFSDAVRequire([_fileManager moveURL:dir1 toURL:dir2 withSourceETag:dirInfo.ETag overwrite:NO error:&error], @"Error renaming directory with valid ETag precondition.");
    
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir2 error:&error], @"Error getting info for renamed directory.");
    OFSDAVRequire(dirInfo.exists, @"Directory should exist at new location");
    
    return YES;
}

// Tests the source ETag hasn't changed
- (BOOL)testCollectionRenameFailingDueToETagPrecondition:(NSError **)outError;
{
    [self _updateStatus:@"Testing collection MOVE with out-of-date ETag predicate."];

    NSURL *dir1 = [_baseURL URLByAppendingPathComponent:@"dir-1" isDirectory:YES];
    NSURL *dir2 = [_baseURL URLByAppendingPathComponent:@"dir-2" isDirectory:YES];
    
    NSError *error;
    OFSDAVRequire(dir1 = [_fileManager createDirectoryAtURL:dir1 attributes:nil error:&error], @"Error creating first directory.");
    
    OFSFileInfo *dirInfo;
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir1 error:&error], @"Error getting info for first directory.");
    
    // Add something to the directory to change its ETag
    OFSDAVRequire([_fileManager writeData:[NSData data] toURL:[dir1 URLByAppendingPathComponent:@"file"] atomically:NO error:&error], @"Error writing data to directory.");
    
    // Verify ETag changed
    OFSFileInfo *updatedDirInfo;
    OFSDAVRequire(updatedDirInfo = [_fileManager fileInfoAtURL:dir1 error:&error], @"Error getting info of updated directory.");
    OFSDAVRequire(![updatedDirInfo.ETag isEqual:dirInfo.ETag], @"Directory ETag should have changed due to writing file into it.");
    
    OFSDAVReject([_fileManager moveURL:dir1 toURL:dir2 withSourceETag:dirInfo.ETag overwrite:NO error:&error], @"Directory rename should have failed due to ETag precondition.");
    OFSDAVRequire([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_PRECONDITION_FAILED], @"Error should specify precondition failure.");
    
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir2 error:&error], @"Error getting info for rename directory.");
    OFSDAVReject(dirInfo.exists, @"Directory should not have been renamed.");
    
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
        OFSDAVRequire(dirA = [_fileManager createDirectoryAtURL:dirA attributes:nil error:&error], @"Error creating first directory.");
        
        // Add something to the directory to change its ETag (so it is differently from ETagB below).
        OFSDAVRequire([_fileManager writeData:[NSData data] toURL:[dirA URLByAppendingPathComponent:@"file1"] atomically:NO error:&error], @"Error writing data to directory.");
        
        
        OFSFileInfo *dirInfo;
        OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dirA error:&error], @"Error getting info for directory.");
        ETagA1 = dirInfo.ETag;
        
        // Add something to the directory to change its ETag
        OFSDAVRequire([_fileManager writeData:[NSData data] toURL:[dirA URLByAppendingPathComponent:@"file2"] atomically:NO error:&error], @"Error writing another file to directory.");
        
        // Verify ETag changed
        OFSFileInfo *updatedDirInfo;
        OFSDAVRequire(updatedDirInfo = [_fileManager fileInfoAtURL:dirA error:&error], @"Error getting info for updated directory.");
        ETagA2 = updatedDirInfo.ETag;
        
        OFSDAVRequire(![ETagA1 isEqual:ETagA2], @"Directory ETag should have changed due to writing file into it.");
    }
    
    NSURL *dirB = [_baseURL URLByAppendingPathComponent:@"dir-b" isDirectory:YES];
    NSString *ETagB;
    {
        NSError *error;
        OFSDAVRequire(dirB = [_fileManager createDirectoryAtURL:dirB attributes:nil error:&error], @"Error creating directory.");
        
        OFSFileInfo *dirInfo;
        OFSDAVRequire (dirInfo = [_fileManager fileInfoAtURL:dirB error:&error], @"Error getting directory info.");
        ETagB = dirInfo.ETag;
        
        // Make sure our tests below aren't spurious
        OFSDAVReject([ETagA1 isEqual:ETagB], @"ETags should have differed.");
        OFSDAVReject([ETagA2 isEqual:ETagB], @"ETags should have differed.");
    }
    
    // Attempt with the old ETag should fail
    {
        NSError *error;
        OFSFileInfo *dirInfo;
        
        OFSDAVReject([_fileManager moveURL:dirB toURL:dirA withDestinationETag:ETagA1 overwrite:YES error:&error], @"Move should have failed due to ETag precondition.");
        OFSDAVRequire([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_PRECONDITION_FAILED], @"Error should specify precondition failure.");
        
        error = nil;
        OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dirB error:&error], @"Error getting info for source URL.");
        OFSDAVRequire(dirInfo.exists, @"Source directory should still be at its original location.");
        OFSDAVRequire([dirInfo.ETag isEqual:ETagB], @"Source directory should still have its original ETag.");
        
        error = nil;
        OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dirA error:&error], @"Error getting info for destination URL.");
        OFSDAVRequire(dirInfo.exists, @"Destination directory should still exist.");
        OFSDAVRequire([dirInfo.ETag isEqual:ETagA2], @"Destination directory should still have the updated ETag");
    }
    
    // Attempt with the current ETag should work
    {
        NSError *error;
        OFSFileInfo *dirInfo;
        
        OFSDAVRequire([_fileManager moveURL:dirB toURL:dirA withDestinationETag:ETagA2 overwrite:YES error:&error], @"Error while replacing directory.");
        
        error = nil;
        OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dirB error:&error], @"Error getting info for source URL.");
        OFSDAVReject(dirInfo.exists, @"Source directory should have been moved.");
        
        error = nil;
        OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dirA error:&error], @"Error getting info for destination URL.");
        OFSDAVRequire(dirInfo.exists, @"Destination directory should exist.");
        OFSDAVRequire([dirInfo.ETag isEqual:ETagB], @"Destination directory should have the new ETag.");
    }
    
    return YES;
}

- (BOOL)testCollectionCopyFailingDueToETagPrecondition:(NSError **)outError;
{
    [self _updateStatus:@"Testing collection COPY with out-of-date ETag predicate."];
    
    NSURL *dir1 = [_baseURL URLByAppendingPathComponent:@"dir-1" isDirectory:YES];
    NSURL *dir2 = [_baseURL URLByAppendingPathComponent:@"dir-2" isDirectory:YES];
    
    NSError *error;
    OFSDAVRequire(dir1 = [_fileManager createDirectoryAtURL:dir1 attributes:nil error:&error], @"Error creating first directory.");
    
    OFSFileInfo *dirInfo;
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir1 error:&error], @"Error getting info for first directory.");
    
    // Add something to the directory to change its ETag
    OFSDAVRequire([_fileManager writeData:[NSData data] toURL:[dir1 URLByAppendingPathComponent:@"file"] atomically:NO error:&error], @"Error writing data to directory.");
    
    // Verify ETag changed
    OFSFileInfo *updatedDirInfo;
    OFSDAVRequire(updatedDirInfo = [_fileManager fileInfoAtURL:dir1 error:&error], @"Error getting info of updated directory.");
    OFSDAVRequire(![updatedDirInfo.ETag isEqual:dirInfo.ETag], @"Directory ETag should have changed due to writing file into it.");
    
    OFSDAVReject([_fileManager copyURL:dir1 toURL:dir2 withSourceETag:dirInfo.ETag overwrite:NO error:&error], @"Directory copy should have failed due to ETag precondition.");
    OFSDAVRequire([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_PRECONDITION_FAILED], @"Error should specify precondition failure.");
    
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir2 error:&error], @"Error getting info for destination directory.");
    OFSDAVReject(dirInfo.exists, @"Directory should not have been copied.");
    
    return YES;
}

- (BOOL)testCollectionCopySucceedingWithETagPrecondition:(NSError **)outError;
{
    [self _updateStatus:@"Testing collection COPY with current ETag predicate."];
    
    NSURL *dir1 = [_baseURL URLByAppendingPathComponent:@"dir-1" isDirectory:YES];
    NSURL *dir2 = [_baseURL URLByAppendingPathComponent:@"dir-2" isDirectory:YES];
    
    NSError *error;
    OFSDAVRequire(dir1 = [_fileManager createDirectoryAtURL:dir1 attributes:nil error:&error], @"Error creating first directory.");
    
    OFSFileInfo *dirInfo;
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir1 error:&error], @"Error getting info for first directory.");
    
    // Add something to the directory to change its ETag
    OFSDAVRequire([_fileManager writeData:[NSData data] toURL:[dir1 URLByAppendingPathComponent:@"file"] atomically:NO error:&error], @"Error writing data to directory.");
    
    // Verify ETag changed
    OFSFileInfo *updatedDirInfo;
    OFSDAVRequire(updatedDirInfo = [_fileManager fileInfoAtURL:dir1 error:&error], @"Error getting info of updated directory.");
    OFSDAVRequire(![updatedDirInfo.ETag isEqual:dirInfo.ETag], @"Directory ETag should have changed due to writing file into it.");
    
    OFSDAVRequire([_fileManager copyURL:dir1 toURL:dir2 withSourceETag:updatedDirInfo.ETag overwrite:NO error:&error], @"Directory copy should succeed with ETag precondition.");
    
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir2 error:&error], @"Error getting info for copied directory.");
    OFSDAVRequire(dirInfo.exists, @"Directory should have been copied.");
    
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:[dir2 URLByAppendingPathComponent:@"file"] error:&error], @"Error getting copied child info");
    OFSDAVRequire(dirInfo.exists, @"Child file should have been copied.");

    return YES;
}

- (BOOL)testPropfindFailingDueToETagPrecondition:(NSError **)outError;
{
    [self _updateStatus:@"Testing PROPFIND with out-of-date ETag predicate."];

    NSURL *dir = [_baseURL URLByAppendingPathComponent:@"dir" isDirectory:YES];
    
    NSError *error;
    OFSDAVRequire(dir = [_fileManager createDirectoryAtURL:dir attributes:nil error:&error], @"Error creating directory.");
    
    OFSFileInfo *dirInfo;
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir error:&error], @"Error getting directory info.");
    
    // Add something to the directory to change its ETag
    OFSDAVRequire([_fileManager writeData:[NSData data] toURL:[dir URLByAppendingPathComponent:@"file"] atomically:NO error:&error], @"Error writing file to directory.");
    
    // Verify ETag changed
    OFSFileInfo *updatedDirInfo;
    OFSDAVRequire (updatedDirInfo = [_fileManager fileInfoAtURL:dir error:&error], @"Error getting updated info for directory.");
    OFSDAVReject([updatedDirInfo.ETag isEqual:dirInfo.ETag], @"Directory ETag should have changed due to writing file into it.");
    
    NSArray *fileInfos;
    OFSDAVReject(fileInfos = [_fileManager directoryContentsAtURL:dir withETag:dirInfo.ETag collectingRedirects:nil options:OFSDirectoryEnumerationSkipsSubdirectoryDescendants|OFSDirectoryEnumerationSkipsHiddenFiles serverDate:NULL error:&error], @"Expected error getting info for directory with old ETag.");
    OFSDAVRequire([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_PRECONDITION_FAILED], @"Error should specify precondition failure.");
    
    return YES;
}

- (BOOL)testDeleteWithETag:(NSError **)outError;
{
    [self _updateStatus:@"Testing deletion with ETag predicate."];
    
    NSURL *dir = [_baseURL URLByAppendingPathComponent:@"dir" isDirectory:YES];
    
    NSError *error;
    OFSDAVRequire(dir = [_fileManager createDirectoryAtURL:dir attributes:nil error:&error], @"Error creating directory.");
    
    OFSFileInfo *fileInfo;
    OFSDAVRequire(fileInfo = [_fileManager fileInfoAtURL:dir error:&error], @"Error getting info for directory.");
    
    // Add something to the directory to change its ETag
    OFSDAVRequire([_fileManager writeData:[NSData data] toURL:[dir URLByAppendingPathComponent:@"file"] atomically:NO error:&error], @"Error writing file to directory.");
    
    OFSDAVReject([_fileManager deleteURL:dir withETag:fileInfo.ETag error:&error], @"Delete with the old ETag should fail");
    
    OFSDAVRequire(fileInfo = [_fileManager fileInfoAtURL:dir error:&error], @"Error getting updated info for directory.");
    OFSDAVRequire([_fileManager deleteURL:dir withETag:fileInfo.ETag error:&error], @"Delete with the new ETag should succeed.");
    
    return YES;
}

#endif

// This is slow, but we'd like to have some confidence that the ETag of a directory reliably changes when new files are added.
#if 0
- (BOOL)testCollectionETagDistributionVsAddMultipleFiles:(NSError **)outError;
{
    [self _updateStatus:@"Testing ETag distribution when adding multiple files."];

    NSURL *dir = [_baseURL URLByAppendingPathComponent:@"dir" isDirectory:YES];
    
    NSError *error;
    OFSDAVRequire(dir = [_fileManager createDirectoryAtURL:dir attributes:nil error:&error], @"Error creating directory.");
    
    NSMutableSet *seenETags = [NSMutableSet new];
    
    OFSFileInfo *dirInfo;
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir error:&error], @"Error getting info for directory.");
    [seenETags addObject:dirInfo.ETag];
    
    for (NSUInteger fileIndex = 0; fileIndex < 1000; fileIndex++) {
        NSURL *file = [dir URLByAppendingPathComponent:[NSString stringWithFormat:@"file%ld", fileIndex]];
        OFSDAVRequire([_fileManager writeData:[NSData data] toURL:file atomically:NO error:&error], @"Error writing file to directory.");
        
        OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir error:&error], @"Error getting updated info for directory.");
        
        OFSDAVReject([seenETags member:dirInfo.ETag], @"should not repeat ETags");
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
        OFSDAVRequire([_fileManager writeData:OFRandomCreateDataOfLength(16) toURL:file atomically:NO error:&error], @"Error writing file.");
        
        OFSFileInfo *fileInfo;
        OFSDAVRequire(fileInfo = [_fileManager fileInfoAtURL:file error:&error], @"Error getting info for file.");
        
        if ([seenETags member:fileInfo.ETag])
            NSLog(@"Duplicate ETag \"%@\"", fileInfo.ETag);
        [seenETags addObject:fileInfo.ETag];
    }
    NSLog(@"%ld seenETags", [seenETags count]);
    OFSDAVRequire([seenETags count] == 1000, @"ETag repeated.");

    return YES;
}
#endif

#if 0 // Fails; the directory ETag covers only 8 values for 1000 modifications
- (BOOL)testCollectionETagDistributionVsModifyFile:(NSError **)outError;
{
    [self _updateStatus:@"Testing collection ETag distribution when modifying a single contained file."];

    NSURL *dir = [_baseURL URLByAppendingPathComponent:@"dir" isDirectory:YES];
    
    NSError *error;
    OFSDAVRequire(dir = [_fileManager createDirectoryAtURL:dir attributes:nil error:&error], @"Error creating directory.");
    
    NSMutableSet *seenETags = [NSMutableSet new];
    
    OFSFileInfo *dirInfo;
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir error:&error], @"Error getting info for directory.");
    [seenETags addObject:dirInfo.ETag];
    
    OFRandomState *state = OFRandomStateCreate();
    
    NSURL *file = [dir URLByAppendingPathComponent:@"file"];
    
    for (NSUInteger fileIndex = 0; fileIndex < 1000; fileIndex++) {
        NSUInteger fileLength = OFRandomNextState64(state) % 1024;
        OFSDAVRequire([_fileManager writeData:[NSData randomDataOfLength:fileLength] toURL:file atomically:NO error:&error], @"Error writing file to directory.");
        
        OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir error:&error], @"Error getting updated info for directory.");
        
        OFSDAVReject([seenETags member:dirInfo.ETag], @"ETag repeated.");
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
    OFSDAVRequire(dir = [_fileManager createDirectoryAtURL:dir attributes:nil error:&error], @"Error creating directory.");
    
    NSMutableSet *seenETags = [NSMutableSet new];
    
    OFSFileInfo *dirInfo;
    OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir error:&error], @"Error getting info for directory.");
    [seenETags addObject:dirInfo.ETag];
    
    NSURL *file = [dir URLByAppendingPathComponent:@"file"];
    
    for (NSUInteger fileIndex = 0; fileIndex < 1000; fileIndex++) {
        OFSDAVRequire([_fileManager writeData:[NSData data] toURL:file atomically:NO error:&error], @"Error writing file to directory.");
        
        OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir error:&error], @"Error getting updated info for directory.");
        [seenETags addObject:dirInfo.ETag];
        
        OFSDAVRequire([_fileManager deleteURL:file error:&error], @"Error deleting file.");
        
        OFSDAVRequire(dirInfo = [_fileManager fileInfoAtURL:dir error:&error], @"Error getting updated info for directory.");
        
        [seenETags addObject:dirInfo.ETag];
        OFSDAVReject([seenETags member:dirInfo.ETag], @"ETag repeated.");
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
    OFSDAVRequire([_fileManager moveURL:parent_tmp_doc toURL:parent_doc withDestinationETag:parent_doc_info.ETag overwrite:YES error:&error], @"Should be able to move a file over an existing file when overwrite is enabled.");

    // Check that the modification date of the parent has changed.
    NSDate *originalDate = parent_info.lastModifiedDate;
    DAV_update_info(parent);
    OFSDAVRequire(OFNOTEQUAL(originalDate, parent_info.lastModifiedDate), @"When a file is moved into a directory and replaces another file, the directory's modification date should change.");
    
    return YES;
}

- (BOOL)testServerDateMovesForward:(NSError **)outError;
{
    __autoreleasing NSError *error;
    
    DAV_mkdir(dir);
    
    OFSFileInfo *info;
    __autoreleasing NSDate *originalDate;
    OFSDAVRequire(info = [_fileManager fileInfoAtURL:dir serverDate:&originalDate error:&error], @"Error getting directory info.");
    OFSDAVRequire(originalDate, @"Server responses should include a Date header with the server's date and time.");
    
    sleep(1);
    
    __autoreleasing NSDate *laterDate;
    OFSDAVRequire(info = [_fileManager fileInfoAtURL:dir serverDate:&laterDate error:&error], @"Error getting directory info.");
    
    OFSDAVRequire(laterDate, @"Server responses should include a Date header with the server's date and time.");
    OFSDAVRequire([laterDate isAfterDate:originalDate], @"The date returned by a server's Date header should move forward every second.");

    return YES;
}

- (BOOL)testMoveFileIfMissing:(NSError **)outError;
{
    NSURL *main = _baseURL;
    
    __autoreleasing NSError *error;
    DAV_write_at(main, a, [NSData data]);
    DAV_write_at(main, b, [NSData data]);
    
    NSURL *main_c = [main URLByAppendingPathComponent:@"c" isDirectory:NO];
    
    OFSDAVRequire([_fileManager moveURL:main_a toMissingURL:main_c error:&error], @"Move without overwrite should succeed when moving a plain file to an empty location.");
    OFSDAVReject([_fileManager moveURL:main_b toMissingURL:main_c error:&error], @"Move without overwrite should fail when moving a plain file to a location that is already in use.");
    
    OFSDAVRequire([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_PRECONDITION_FAILED], @"Moving a file to a location which already exists should return a precondition error (%d) rather than an error in domain %@ with code %ld.", OFS_HTTP_PRECONDITION_FAILED, error.domain, error.code);
    
    return YES;
}

- (BOOL)testMoveCollectionIfMissing:(NSError **)outError;
{
    NSURL *main = _baseURL;
    
    __autoreleasing NSError *error;
    DAV_mkdir(a);
    DAV_mkdir(b);
    
    NSURL *c = [main URLByAppendingPathComponent:@"c" isDirectory:YES];
    
    OFSDAVRequire([_fileManager moveURL:a toMissingURL:c error:&error], @"Move without overwrite should succeed when moving a directory to an empty location.");
    OFSDAVReject([_fileManager moveURL:b toMissingURL:c error:&error], @"Move without overwrite should fail when moving a directory to a location that is already in use.");
    
    OFSDAVRequire([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_PRECONDITION_FAILED], @"Moving a directory to a location which already exists should return a precondition error (%d) rather than an error in domain %@ with code %ld.", OFS_HTTP_PRECONDITION_FAILED, error.domain, error.code);
    
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
    
    // Apache returns OFS_HTTP_INTERNAL_SERVER_ERROR for both these ><
    OFSDAVReject([_fileManager moveURL:main_a toMissingURL:destB error:&error], @"Should not be able to move a file inside a missing collection.");
    OFSDAVReject([_fileManager moveURL:main_a toMissingURL:destC error:&error], @"Should not be able to move a file inside a deeply missing collection.");
    
    return YES;
}

- (BOOL)testMoveCollectionToDeeplyMissingCollection:(NSError **)outError;
{
    NSURL *main = _baseURL;
    __autoreleasing NSError *error;
    
    DAV_mkdir(a);
    
    NSURL *dirB = [main URLByAppendingPathComponent:@"b" isDirectory:YES];
    NSURL *destB = [dirB URLByAppendingPathComponent:@"file" isDirectory:NO];
    
    NSURL *dirC = [dirB URLByAppendingPathComponent:@"c" isDirectory:YES];
    NSURL *destC = [dirC URLByAppendingPathComponent:@"file" isDirectory:NO];
    
    // Apache returns OFS_HTTP_INTERNAL_SERVER_ERROR for both these ><
    OFSDAVReject([_fileManager moveURL:a toMissingURL:destB error:&error], @"Should not be able to move a collection inside a missing collection.");
    OFSDAVReject([_fileManager moveURL:a toMissingURL:destC error:&error], @"Should not be able to move a collection inside a deeply missing collection.");
    
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
    OFSDAVRequire(compressedData = [xmlData compressedData:&error], @"[Internal error: data compression should succeed.]");;
    
    NSURL *main = _baseURL;
    DAV_write_at(main, file, compressedData);
    
    NSData *readData;
    OFSDAVRequire((readData = [_fileManager dataWithContentsOfURL:main_file error:&error]), @"Fetch of compressed data should work.");
    OFSDAVRequire([compressedData isEqualToData:readData], @"Server should not automatically assign a compressed MIME type, because it triggers automatic decompression when the file is retrieved.");
    
    return YES;
}

// This doesn't work in Apache. They only validate the If headers vs a small set of resources, not including those only mentioned in the If headers. To me the spec says they should, but fixing this is likely to be hard enough that we'll just avoid using it: "Additionally, the mere fact that a state token appears in an If header means that it has been "submitted" with the request. In general, this is used to indicate that the client has knowledge of that state token. The semantics for submitting a state token depend on its type (for lock tokens, please refer to Section 6).
#if 0
// <http://www.webdav.org/specs/rfc4918.html#rfc.section.10.4> "The If request header is intended to have similar functionality to the If-Match header defined in Section 14.24 of [RFC2616]"
// <http://tools.ietf.org/html/rfc2616#section-14.24> "or if "*" is given and any current entity exists for that resource, then the server MAY perform the requested method as if the If-Match header field did not exist."
- (BOOL)testReplaceCollectionIfContainsGivenFile:(NSError **)outError;
{
    __autoreleasing NSError *error;

    // Make sure we have URL encoded characters
    NSURL *src = [_baseURL URLByAppendingPathComponent:@"src dir" isDirectory:YES];
    OFSDAVRequire(src = [_fileManager createDirectoryAtURL:src attributes:nil error:&error], @"Error creating source directory.");
    NSURL *dst = [_baseURL URLByAppendingPathComponent:@"dst dir" isDirectory:YES];
    OFSDAVRequire(dst = [_fileManager createDirectoryAtURL:dst attributes:nil error:&error], @"Error creating destination directory.");

    NSURL *dst_tag_missing = [dst URLByAppendingPathComponent:@"tag file" isDirectory:NO];
    OFSDAVReject([_fileManager moveURL:src toURL:dst ifURLExists:dst_tag_missing error:&error], @"dst/tag is missing, so this should fail");
    
    DAV_write_at(dst, tag, [NSData data]);
    OFSDAVRequire([_fileManager moveURL:src toURL:dst ifURLExists:dst_tag_missing error:&error], @"dst/tag is now present, so this should work");
    
    return YES;
}
#endif

// Support for testing the failure path.
- (BOOL)testFail:(NSError **)outError;
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"OFSDAVConformanceTestFailIntentionally"]) {
        __autoreleasing NSError *error;
        OFSDAVRequire(NO, @"Failing intentionally to test failure path because OFSDAVConformanceTestFailIntentionally is set.");
    }
    
    return YES;
}

#pragma mark - Private

- (void)_updateStatus:(NSString *)status;
{
    if (_statusChanged) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            _statusChanged(status);
        }];
    }
}

@end
