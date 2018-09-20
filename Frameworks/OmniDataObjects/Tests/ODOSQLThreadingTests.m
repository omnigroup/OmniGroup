// Copyright 2017-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

#import <OmniDataObjects/ODODatabase.h>
#import <OmniDataObjects/ODOSQLConnection.h>
#import <OmniDataObjects/ODOSQLStatement.h>

RCS_ID("$Id$");

#if OB_ARC
#error ODOSQLThreadingTests.m should not be compiled with ARC. It counts on managing the lifecycle of objects explicitly in some test cases.
#endif

@interface ODOSQLThreadingTests : ODOTestCase <OBMissedDeallocationObserver>
@end

@implementation ODOSQLThreadingTests

+ (NSString *)selectAllMetadataSQL;
{
    return @"SELECT * FROM ODOMetadata";
}

- (void)missedDeallocationsUpdated:(NSSet<OBMissedDeallocation *> *)missedDeallocations;
{
    if ([missedDeallocations count] > 0) {
        XCTFail(@"Missed deallocation of one or more objects during test");
    }
}

- (void)setUp;
{
    [super setUp];
    [OBMissedDeallocation setObserver:self];
}

- (void)tearDown;
{
    [OBMissedDeallocation setObserver:nil];
    [super tearDown];
}

#pragma mark Tests

- (void)testStatementLifecycleOnMainQueue;
{
    NSError *error = nil;
    ODOSQLStatement *statement = [[ODOSQLStatement alloc] initWithConnection:_database.connection sql:[[self class] selectAllMetadataSQL] error:&error];
    XCTAssertNotNil(statement);
    XCTAssertNil(error);
    
    [_database.connection performSQLAndWaitWithError:&error block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        XCTAssertTrue([statement prepareIfNeededWithSQLite:sqlite error:blockError]);
    }];
    
    XCTAssertNoThrow([statement release]);
}

- (void)testStatementDeallocOnSQLiteQueue;
{
    NSError *error = nil;
    ODOSQLStatement *statement = [[ODOSQLStatement alloc] initWithConnection:_database.connection sql:[[self class] selectAllMetadataSQL] error:&error];
    XCTAssertNotNil(statement);
    XCTAssertNil(error);
    
    [_database.connection performSQLAndWaitWithError:&error block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        XCTAssertTrue([statement prepareIfNeededWithSQLite:sqlite error:blockError]);
        XCTAssertNoThrow([statement release]);
    }];
}

- (void)testConnectionDeallocBeforeStatementDealloc;
{
    NSError *error = nil;
    ODOSQLStatement *statement = [[ODOSQLStatement alloc] initWithConnection:_database.connection sql:[[self class] selectAllMetadataSQL] error:&error];
    XCTAssertNotNil(statement);
    XCTAssertNil(error);
    
    [_database.connection performSQLAndWaitWithError:&error block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        XCTAssertTrue([statement prepareIfNeededWithSQLite:sqlite error:blockError]);
    }];
    
    OBExpectDeallocation(_database.connection);
    
    XCTAssertTrue([statement isPrepared]);
    XCTAssertThrows([_database disconnect:&error]);
    XCTAssertNoThrow([statement release]);
}

- (void)testManyConcurrentStatements;
{
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 20;
    queue.suspended = YES;
    
    for (NSUInteger i = 0; i < 2000; i++) {
        [queue addOperationWithBlock:^{
            uint64_t rowCount = UINT64_MAX;
            NSError *error = nil;
            XCTAssertTrue([_database fetchCommittedRowCount:&rowCount fromEntity:[_database.model entityNamed:@"Master"] matchingPredicate:nil error:&error]);
            XCTAssertNil(error);
            XCTAssertEqual(0UL, rowCount);
        }];
    }
    
    queue.suspended = NO;
    [queue waitUntilAllOperationsAreFinished];
    
    [queue release];
}

@end
