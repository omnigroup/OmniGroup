// Copyright 2019 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

#import <OmniFoundation/OFNull.h>
#import <OmniDataObjects/ODOFetchExtremum.h>

typedef void (^ODOFetchAggregationTestCallbackBlock)(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate);

@interface ODOFetchAggregationTests : ODOTestCase
@end

@implementation ODOFetchAggregationTests

- (ODOTestCaseOptionalDate *)insertOptionalDateObjectWithDate:(NSDate *)date save:(BOOL)save;
{
    ODOTestCaseOptionalDate *optionalDate = [[ODOTestCaseOptionalDate alloc] initWithEntity:[ODOTestCaseModel() entityNamed:ODOTestCaseOptionalDateEntityName] primaryKey:nil insertingIntoEditingContext:_editingContext];
    optionalDate.date = date;
    
    if (save) {
        NSError *error = nil;
        XCTAssertTrue([self save:&error]);
    }
    
    return optionalDate;
}

- (void)fetchDateExtremaWithPredicate:(nullable NSPredicate *)predicate performingBlock:(ODOFetchAggregationTestCallbackBlock)blk;
{
    ODOEntity *entity = [ODOTestCaseModel() entityNamed:ODOTestCaseOptionalDateEntityName];
    ODOAttribute *dateAttribute = OB_CHECKED_CAST(ODOAttribute, [entity propertyNamed:ODOTestCaseOptionalDateDate]);
    NSArray *attributes = @[ [entity propertyNamed:ODOTestCaseOptionalDatePk], dateAttribute ];
    NSError *error = nil;
    
    for (NSNumber *extremumNumber in @[ @(ODOFetchMinimum), @(ODOFetchMaximum) ]) {
        ODOFetchExtremum extremum = [extremumNumber unsignedIntegerValue];
        NSArray *attributeValues = [_editingContext.database fetchCommittedAttributes:attributes fromEntity:entity havingExtremum:extremum forAttribute:dateAttribute matchingPredicate:predicate error:&error];
        if (attributeValues == nil) {
            XCTFail(@"Unable to fetch minimum committed date: %@", error);
            return;
        }
        
        id (^unwrapNull)(id) = ^(id anObject) {
            return OFISNULL(anObject) ? nil : anObject;
        };
        
        NSString *primaryKey = OB_CHECKED_CAST_OR_NIL(NSString, unwrapNull([attributeValues firstObject][0]));
        NSDate *extremeDate = OB_CHECKED_CAST_OR_NIL(NSDate, unwrapNull([attributeValues firstObject][1]));
        XCTAssertEqual(primaryKey == nil, extremeDate == nil); // should have neither or both
        blk(extremum, primaryKey, extremeDate);
    }
}

- (void)fetchDateExtremaPerformingBlock:(ODOFetchAggregationTestCallbackBlock)blk;
{
    [self fetchDateExtremaWithPredicate:nil performingBlock:blk];
}

- (void)testExtremaWithNoObjects;
{
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        XCTAssertNil(primaryKey);
        XCTAssertNil(extremeDate);
    }];
}

- (void)testExtremaOfSingleObjectWithoutPropertyValue;
{
    [self insertOptionalDateObjectWithDate:nil save:YES];
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        XCTAssertNil(primaryKey);
        XCTAssertNil(extremeDate);
    }];
}

- (void)testExtremaOfSingleObjectWithPropertyValue;
{
    NSDate *date = [NSDate date];
    ODOTestCaseOptionalDate *object = [self insertOptionalDateObjectWithDate:date save:YES];
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        XCTAssertEqualObjects([[object objectID] primaryKey], primaryKey);
        XCTAssertEqualObjects(date, extremeDate);
    }];
}

- (void)testExtremaOfTwoObjectsWithoutPropertyValues;
{
    [self insertOptionalDateObjectWithDate:nil save:YES];
    [self insertOptionalDateObjectWithDate:nil save:YES];
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        XCTAssertNil(primaryKey);
        XCTAssertNil(extremeDate);
    }];
}

- (void)testExtremaOfTwoObjectsWithSamePropertyValues;
{
    NSDate *date = [NSDate date];
    ODOTestCaseOptionalDate *a = [self insertOptionalDateObjectWithDate:date save:YES];
    ODOTestCaseOptionalDate *b = [self insertOptionalDateObjectWithDate:date save:YES];
    NSSet *primaryKeys = [NSSet setWithObjects:a.objectID.primaryKey, b.objectID.primaryKey, nil];
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        XCTAssertNotNil(primaryKey);
        XCTAssertTrue([primaryKeys containsObject:primaryKey]);
        XCTAssertEqualObjects(date, extremeDate);
    }];
}

- (void)testExtremaOfTwoObjectsWithDifferentPropertyValues;
{
    ODOTestCaseOptionalDate *a = [self insertOptionalDateObjectWithDate:[NSDate dateWithTimeIntervalSinceReferenceDate:10] save:YES];
    ODOTestCaseOptionalDate *b = [self insertOptionalDateObjectWithDate:[NSDate dateWithTimeIntervalSinceReferenceDate:20] save:YES];
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        switch (extremum) {
            case ODOFetchMinimum: {
                XCTAssertEqualObjects(a.objectID.primaryKey, primaryKey);
                XCTAssertEqualObjects(a.date, extremeDate);
                break;
            }
            case ODOFetchMaximum: {
                XCTAssertEqualObjects(b.objectID.primaryKey, primaryKey);
                XCTAssertEqualObjects(b.date, extremeDate);
                break;
            }
        }
    }];
}

- (void)testExtremaOfTwoObjectsWithSomeNilPropertyValues;
{
    NSDate *date = [NSDate date];
    ODOTestCaseOptionalDate *hasDate = [self insertOptionalDateObjectWithDate:date save:YES];
    ODOTestCaseOptionalDate *noDate = [self insertOptionalDateObjectWithDate:nil save:YES];
    OB_UNUSED_VALUE(noDate);
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        XCTAssertEqualObjects(hasDate.objectID.primaryKey, primaryKey);
        XCTAssertEqualObjects(date, extremeDate);
    }];
}

- (void)testExtremaOfManyObjectsWithMixedPropertyValues;
{
    NSUInteger objectCount = 100;
    assert(objectCount % 2 == 0); // for test sanity
    
    NSMutableArray *objects = [NSMutableArray array];
    for (NSUInteger i = 0; i < objectCount; i++) {
        NSDate *date = (i % 2 == 0) ? [NSDate dateWithTimeIntervalSinceReferenceDate:i] : nil;
        ODOTestCaseOptionalDate *object = [self insertOptionalDateObjectWithDate:date save:YES];
        [objects addObject:object];
    }
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        ODOTestCaseOptionalDate *expected = nil;
        switch (extremum) {
            case ODOFetchMinimum: expected = objects[0]; break;
            case ODOFetchMaximum: expected = objects[objectCount - 2]; break;
        }
        
        XCTAssertEqualObjects(expected.objectID.primaryKey, primaryKey);
        XCTAssertEqualObjects(expected.date, extremeDate);
    }];
}

- (void)testExtremaOfObjectsMismatchingPredicate;
{
    [self insertOptionalDateObjectWithDate:[NSDate date] save:YES];
    
    NSPredicate *flaggedPredicate = [NSPredicate predicateWithFormat:@"%K == TRUE", ODOTestCaseOptionalDateFlag];
    [self fetchDateExtremaWithPredicate:flaggedPredicate performingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        XCTAssertNil(primaryKey);
        XCTAssertNil(extremeDate);
    }];
}

- (void)testExtremaOfUnsavedInsertedObject;
{
    [self insertOptionalDateObjectWithDate:[NSDate date] save:NO];
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        XCTAssertNil(primaryKey);
        XCTAssertNil(extremeDate);
    }];
}

- (void)testExtremaOfUnsavedModifiedObjectWithDate;
{
    ODOTestCaseOptionalDate *object = [self insertOptionalDateObjectWithDate:nil save:YES];
    object.date = [NSDate date];
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        XCTAssertNil(primaryKey);
        XCTAssertNil(extremeDate);
    }];
}

- (void)testExtremaOfUnsavedModifiedObjectWithoutDate;
{
    NSDate *date = [NSDate date];
    ODOTestCaseOptionalDate *object = [self insertOptionalDateObjectWithDate:date save:YES];
    object.date = nil;
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        XCTAssertEqualObjects(object.objectID.primaryKey, primaryKey);
        XCTAssertEqualObjects(date, extremeDate);
    }];
}

- (void)testExtremaOfUnsavedModifiedObjectsWithAlteredDates;
{
    // start with A before B…
    ODOTestCaseOptionalDate *a = [self insertOptionalDateObjectWithDate:[NSDate dateWithTimeIntervalSinceReferenceDate:0] save:YES];
    ODOTestCaseOptionalDate *b = [self insertOptionalDateObjectWithDate:[NSDate dateWithTimeIntervalSinceReferenceDate:10] save:YES];
    
    // …then flip A to come after B
    a.date = [NSDate dateWithTimeIntervalSinceReferenceDate:20];
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        switch (extremum) {
            case ODOFetchMinimum: {
                XCTAssertEqualObjects(a.objectID.primaryKey, primaryKey);
                XCTAssertEqualObjects([NSDate dateWithTimeIntervalSinceReferenceDate:0], extremeDate);
                break;
            }
            case ODOFetchMaximum: {
                XCTAssertEqualObjects(b.objectID.primaryKey, primaryKey);
                XCTAssertEqualObjects([NSDate dateWithTimeIntervalSinceReferenceDate:10], extremeDate);
                break;
            }
        }
    }];
}

- (void)testExtremaWithUnsavedObjectModifiedToMatchPredicate;
{
    // start with A, not B…
    ODOTestCaseOptionalDate *a = [self insertOptionalDateObjectWithDate:[NSDate dateWithTimeIntervalSinceReferenceDate:0] save:YES];
    ODOTestCaseOptionalDate *b = [self insertOptionalDateObjectWithDate:nil save:YES];
    
    // …then set up B so that it matches one extremum
    b.date = [NSDate dateWithTimeIntervalSinceReferenceDate:10];
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        XCTAssertEqualObjects(a.objectID.primaryKey, primaryKey);
        XCTAssertEqualObjects(a.date, extremeDate);
    }];
}

- (void)testExtremaWithUnsavedDeletedObject;
{
    // start with A and B…
    ODOTestCaseOptionalDate *a = [self insertOptionalDateObjectWithDate:[NSDate dateWithTimeIntervalSinceReferenceDate:0] save:YES];
    ODOTestCaseOptionalDate *b = [self insertOptionalDateObjectWithDate:[NSDate dateWithTimeIntervalSinceReferenceDate:10] save:YES];
    
    // …then delete A, so B is the only remaining match
    NSError *error = nil;
    OBShouldNotError([_editingContext deleteObject:a error:&error]);
    
    [self fetchDateExtremaPerformingBlock:^(ODOFetchExtremum extremum, NSString * _Nullable primaryKey, NSDate * _Nullable extremeDate) {
        switch (extremum) {
            case ODOFetchMinimum: {
                XCTAssertEqualObjects(a.objectID.primaryKey, primaryKey);
                XCTAssertEqualObjects([NSDate dateWithTimeIntervalSinceReferenceDate:0], extremeDate);
                break;
            }
            case ODOFetchMaximum: {
                XCTAssertEqualObjects(b.objectID.primaryKey, primaryKey);
                XCTAssertEqualObjects([NSDate dateWithTimeIntervalSinceReferenceDate:10], extremeDate);
                break;
            }
        }
    }];
}

@end
