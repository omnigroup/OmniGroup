// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

RCS_ID("$Id$")

@interface ODOAttributeTypeTests : ODOTestCase
@end

@implementation ODOAttributeTypeTests

- (void)testSaveAndLoadAllAttributeTypes;
{
    ODOTestCaseAllAttributeTypes *allAttributeTypes = [[[ODOTestCaseAllAttributeTypes alloc] initWithEntity:[ODOTestCaseModel() entityNamed:ODOTestCaseAllAttributeTypesEntityName] primaryKey:nil insertingIntoEditingContext:_editingContext] autorelease];

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
    
    ODOObjectID *objectID = [[[allAttributeTypes objectID] retain] autorelease];
    
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

@end
