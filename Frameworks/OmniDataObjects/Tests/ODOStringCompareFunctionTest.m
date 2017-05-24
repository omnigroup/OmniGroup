// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

RCS_ID("$Id$")

@interface ODOLikeTests : ODOTestCase
@end

@implementation ODOLikeTests

// TODO: Test passing NULL
// TODO: Test passing case/diacritical on both search and text
// Contains and diacritical are only on 10.5 and iPhone, so doing tests of those here doesn't pan out.
- (void)_setupWithStrings:(NSArray *)strings;
{    
    ODOEntity *entity = [[_database model] entityNamed:ODOTestCaseMasterEntityName];
    
    NSUInteger stringIndex = [strings count];
    while (stringIndex--) {
        NSString *string = [strings objectAtIndex:stringIndex];

        ODOTestCaseMaster *master = [[[ODOTestCaseMaster alloc] initWithEntity:entity primaryKey:string insertingIntoEditingContext:_editingContext] autorelease];
        [_editingContext processPendingChanges];
        master.name = string;
    }
}

- (NSArray *)_fetchWithType:(NSPredicateOperatorType)type string:(NSString *)string;
{
    NSError *error = nil;
    ODOEntity *entity = [[_database model] entityNamed:ODOTestCaseMasterEntityName];

    NSPredicate *predicate = ODOKeyPathCompareToValuePredicate(@"name", type, string);
    ODOFetchRequest *fetch = [[[ODOFetchRequest alloc] init] autorelease];
    [fetch setEntity:entity];
    [fetch setPredicate:predicate];
    
    NSArray *results;
    OBShouldNotError((results = [_editingContext executeFetchRequest:fetch error:&error]) != nil);
    return results;
}

// 
- (void)testBeginsWithInMemory;
{ 
    [self _setupWithStrings:[NSArray arrayWithObjects:@"spoon", @"name", nil]];
    
    NSArray *results = [self _fetchWithType:NSBeginsWithPredicateOperatorType string:@"sp"];
    
    XCTAssertTrue([results count] == 1);
    
    ODOObject *foundObject = [results lastObject];
    XCTAssertEqualObjects([[foundObject objectID] primaryKey], @"spoon");
}

- (void)testBeginsWithFetch;
{
    NSError *error = nil;
    
    [self _setupWithStrings:[NSArray arrayWithObjects:@"spoon", @"name", nil]];
    
    OBShouldNotError([_editingContext saveWithDate:[NSDate date] error:&error]);
    
    NSArray *results = [self _fetchWithType:NSBeginsWithPredicateOperatorType string:@"sp"];
    
    ODOObject *foundObject = [results lastObject];
    XCTAssertEqualObjects([[foundObject objectID] primaryKey], @"spoon");
}

@end
