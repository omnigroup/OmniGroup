// Copyright 2008-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

#import <OmniFoundation/OFRandom.h>

RCS_ID("$Id$")

OB_REQUIRE_ARC;

@interface ODOAttributeTypeTests : ODOTestCase
@end

@implementation ODOAttributeTypeTests

- (void)testSaveAndLoadAllAttributeTypes;
{
    ODOTestCaseAllAttributeTypes *allAttributeTypes = [[ODOTestCaseAllAttributeTypes alloc] initWithEntity:[ODOTestCaseModel() entityNamed:ODOTestCaseAllAttributeTypesEntityName] primaryKey:nil insertingIntoEditingContext:_editingContext];

    // TODO: We don't currently define any saturation modes for scalar attributes.  We can either be strict and error out or we could be more flexible like SQLite is (though we'd have to bind all ints via the 64-bit path).
    allAttributeTypes.int16 = SHRT_MAX;
    allAttributeTypes.int32 = INT_MAX;
    allAttributeTypes.int64 = LLONG_MAX;
    allAttributeTypes.float32 = FLT_MAX;
    allAttributeTypes.float64 = DBL_MAX;
    allAttributeTypes.string = @"xyzzy";
    allAttributeTypes.boolean = YES;
    allAttributeTypes.date = [NSDate dateWithTimeIntervalSinceReferenceDate:123.0];
    
    unsigned char bytes[4] = {0xde, 0xad, 0xbe, 0xef};
    allAttributeTypes.data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    
    NSError *error = nil;
    OBShouldNotError([_editingContext saveWithDate:[NSDate date] error:&error]);
    
    ODOObjectID *objectID = [allAttributeTypes objectID];
    
    // Refetch the object
    [_editingContext reset];
    
    allAttributeTypes = (ODOTestCaseAllAttributeTypes *)[_editingContext fetchObjectWithObjectID:objectID error:&error];
    OBShouldNotError(allAttributeTypes != nil);
    
    XCTAssertEqual(SHRT_MAX, allAttributeTypes.int16);
    XCTAssertEqual(INT_MAX, allAttributeTypes.int32);
    XCTAssertEqual(LLONG_MAX, allAttributeTypes.int64);
    XCTAssertEqual(FLT_MAX, allAttributeTypes.float32);
    XCTAssertEqual(DBL_MAX, allAttributeTypes.float64);
    XCTAssertEqualObjects(@"xyzzy", allAttributeTypes.string);
    XCTAssertEqual(YES, allAttributeTypes.boolean);
    XCTAssertEqualObjects([NSDate dateWithTimeIntervalSinceReferenceDate:123.0], allAttributeTypes.date);
}

- (void)testOptionalScalarAttributeTypes;
{
    ODOTestCaseOptionalScalarTypes *optionals = [[ODOTestCaseOptionalScalarTypes alloc] initWithEntity:[ODOTestCaseModel() entityNamed:ODOTestCaseOptionalScalarTypesEntityName] primaryKey:nil insertingIntoEditingContext:_editingContext];

    XCTAssertNil(optionals.int16);
    XCTAssertNil(optionals.int32);
    XCTAssertNil(optionals.int64);
    XCTAssertNil(optionals.float32);
    XCTAssertNil(optionals.float64);
    XCTAssertNil(optionals.boolean);

    optionals.int16 = @(SHRT_MAX);
    optionals.int32 = @(INT_MAX);
    optionals.int64 = @(LLONG_MAX);
    optionals.float32 = @(FLT_MAX);
    optionals.float64 = @(DBL_MAX);
    optionals.boolean = @(YES);

    NSError *error = nil;
    OBShouldNotError([_editingContext saveWithDate:[NSDate date] error:&error]);

    // Refetch the object
    ODOObjectID *objectID = [optionals objectID];
    [_editingContext reset];

    optionals = (ODOTestCaseOptionalScalarTypes *)[_editingContext fetchObjectWithObjectID:objectID error:&error];
    OBShouldNotError(optionals != nil);

    XCTAssertEqualObjects(@(SHRT_MAX), optionals.int16);
    XCTAssertEqualObjects(@(INT_MAX), optionals.int32);
    XCTAssertEqualObjects(@(LLONG_MAX), optionals.int64);
    XCTAssertEqualObjects(@(FLT_MAX), optionals.float32);
    XCTAssertEqualObjects(@(DBL_MAX), optionals.float64);
    XCTAssertEqualObjects(@(YES), optionals.boolean);
}

- (void)testNilOptionalScalarAttributeTypes;
{
    ODOTestCaseOptionalScalarTypes *optionals = [[ODOTestCaseOptionalScalarTypes alloc] initWithEntity:[ODOTestCaseModel() entityNamed:ODOTestCaseOptionalScalarTypesEntityName] primaryKey:nil insertingIntoEditingContext:_editingContext];

    optionals.int16 = @(SHRT_MAX);
    optionals.int32 = @(INT_MAX);
    optionals.int64 = @(LLONG_MAX);
    optionals.float32 = @(FLT_MAX);
    optionals.float64 = @(DBL_MAX);
    optionals.boolean = @(YES);

    XCTAssertEqualObjects(@(SHRT_MAX), optionals.int16);
    XCTAssertEqualObjects(@(INT_MAX), optionals.int32);
    XCTAssertEqualObjects(@(LLONG_MAX), optionals.int64);
    XCTAssertEqualObjects(@(FLT_MAX), optionals.float32);
    XCTAssertEqualObjects(@(DBL_MAX), optionals.float64);
    XCTAssertEqualObjects(@(YES), optionals.boolean);

    // Set them back to nil and check

    optionals.int16 = nil;
    optionals.int32 = nil;
    optionals.int64 = nil;
    optionals.float32 = nil;
    optionals.float64 = nil;
    optionals.boolean = nil;

    XCTAssertNil(optionals.int16);
    XCTAssertNil(optionals.int32);
    XCTAssertNil(optionals.int64);
    XCTAssertNil(optionals.float32);
    XCTAssertNil(optionals.float64);
    XCTAssertNil(optionals.boolean);
}

- (void)testMultipleBooleans;
{
    ODOTestCaseMultipleBooleans *bits = [[ODOTestCaseMultipleBooleans alloc] initWithEntity:[ODOTestCaseModel() entityNamed:ODOTestCaseMultipleBooleansEntityName] primaryKey:nil insertingIntoEditingContext:_editingContext];

    for (NSUInteger try = 0; try < 100; try++) {
        uint64_t value = OFRandomNext64();

        bits.b0 = (value >> 0) & 0x1;
        bits.b1 = (value >> 1) & 0x1;
        bits.b2 = (value >> 2) & 0x1;
        bits.b3 = (value >> 3) & 0x1;
        bits.b4 = (value >> 4) & 0x1;
        bits.b5 = (value >> 5) & 0x1;
        bits.b6 = (value >> 6) & 0x1;
        bits.b7 = (value >> 7) & 0x1;
        bits.b8 = (value >> 8) & 0x1;
        bits.b9 = (value >> 9) & 0x1;

        bits.b10 = (value >> 10) & 0x1;
        bits.b11 = (value >> 11) & 0x1;
        bits.b12 = (value >> 12) & 0x1;
        bits.b13 = (value >> 13) & 0x1;
        bits.b14 = (value >> 14) & 0x1;
        bits.b15 = (value >> 15) & 0x1;
        bits.b16 = (value >> 16) & 0x1;
        bits.b17 = (value >> 17) & 0x1;
        bits.b18 = (value >> 18) & 0x1;
        bits.b19 = (value >> 19) & 0x1;

        bits.i0 = (int32_t)((value >> 32) & 0xffffffff);

        // Make sure none of the writes clobbered each other.

        XCTAssertEqual(bits.b0, (value >> 0) & 0x1);
        XCTAssertEqual(bits.b1, (value >> 1) & 0x1);
        XCTAssertEqual(bits.b2, (value >> 2) & 0x1);
        XCTAssertEqual(bits.b3, (value >> 3) & 0x1);
        XCTAssertEqual(bits.b4, (value >> 4) & 0x1);
        XCTAssertEqual(bits.b5, (value >> 5) & 0x1);
        XCTAssertEqual(bits.b6, (value >> 6) & 0x1);
        XCTAssertEqual(bits.b7, (value >> 7) & 0x1);
        XCTAssertEqual(bits.b8, (value >> 8) & 0x1);
        XCTAssertEqual(bits.b9, (value >> 9) & 0x1);

        XCTAssertEqual(bits.b10, (value >> 10) & 0x1);
        XCTAssertEqual(bits.b11, (value >> 11) & 0x1);
        XCTAssertEqual(bits.b12, (value >> 12) & 0x1);
        XCTAssertEqual(bits.b13, (value >> 13) & 0x1);
        XCTAssertEqual(bits.b14, (value >> 14) & 0x1);
        XCTAssertEqual(bits.b15, (value >> 15) & 0x1);
        XCTAssertEqual(bits.b16, (value >> 16) & 0x1);
        XCTAssertEqual(bits.b17, (value >> 17) & 0x1);
        XCTAssertEqual(bits.b18, (value >> 18) & 0x1);
        XCTAssertEqual(bits.b19, (value >> 19) & 0x1);

        XCTAssertEqual(bits.i0, (int32_t)((value >> 32) & 0xffffffff));
    }
}

- (void)testInterleavedScalars;
{
    // Tests a few different orderings of widths of scalars to make sure packing them together works out reasonably.
    ODOTestCaseInterleavedSizeScalars *scalars = [[ODOTestCaseInterleavedSizeScalars alloc] initWithEntity:[ODOTestCaseModel() entityNamed:ODOTestCaseInterleavedSizeScalarsEntityName] primaryKey:nil insertingIntoEditingContext:_editingContext];

    id (^randomValueForKey)(NSString *key) = ^id(NSString *key){
        unichar type;
        if ([key hasPrefix:@"o"]) {
            // Optional
            if (OFRandomNext64() & 0x1) {
                return nil;
            }
            type = [key characterAtIndex:1];
        } else {
            type = [key characterAtIndex:0];
        }

        switch (type) {
            case 's':
                return @((int16_t)OFRandomNext64());
            case 'b':
                return @((BOOL)(OFRandomNext64() & 0x1));
            case 'f':
                return @(OFRandomNextDouble());
            case 'i':
                return @((int)OFRandomNext32());
            default:
                OBASSERT_NOT_REACHED("Unknown type");
                return nil;
        }
    };

    NSArray <NSString *> *propertyKeys = @[@"s0", @"b0", @"f0", @"i0", @"s1", @"b1", @"f1", @"i1", @"s2", @"b2", @"f2", @"i2", @"os2", @"ob2", @"of2", @"oi2"];

    // Repeat the test several times to get different combinations of optionals.
    for (NSUInteger try = 0; try < 100; try++) {

        // For each key, pick a random value and store it.
        for (NSString *key in propertyKeys) {
            id value = randomValueForKey(key);
            [scalars setValue:value forKey:key];

            // For every other key, pick random values and store them.
            for (NSString *otherKey in propertyKeys) {
                if ([otherKey isEqual:key]) {
                    continue;
                }
                [scalars setValue:randomValueForKey(otherKey) forKey:otherKey];
            }

            // The original value should not be changed.
            XCTAssertEqualObjects(value, [scalars valueForKey:key]);
        }
    }
}

- (void)testCalculated;
{
    ODOTestCaseCalculatedProperty *calc = [[ODOTestCaseCalculatedProperty alloc] initWithEntity:[ODOTestCaseModel() entityNamed:ODOTestCaseCalculatedPropertyEntityName] primaryKey:nil insertingIntoEditingContext:_editingContext];

    // Check that the default values got installed
    XCTAssertFalse(calc.b0);
    XCTAssertTrue(calc.b1);

    // Default values
    XCTAssertEqualObjects(calc.xor, @(YES));
    XCTAssertEqualObjects(calc.concat, @"ab");
}

@end

