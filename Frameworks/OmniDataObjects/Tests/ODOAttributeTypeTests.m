// Copyright 2008, 2010, 2014 Omni Development, Inc.  All rights reserved.
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
    ODOTestCaseAllAttributeTypes *allAttributeTypes = [[ODOTestCaseAllAttributeTypes alloc] initWithEditingContext:_editingContext entity:[ODOTestCaseModel() entityNamed:ODOTestCaseAllAttributeTypesEntityName] primaryKey:nil];
    [_editingContext insertObject:allAttributeTypes];
    [allAttributeTypes release];

    // TODO: We don't currently define any saturation modes for scalar attributes.  We can either be strict and error out or we could be more flexible like SQLite is (though we'd have to bind all ints via the 64-bit path).
    allAttributeTypes.int16 = [NSNumber numberWithShort:SHRT_MAX];
    allAttributeTypes.int32 = [NSNumber numberWithInt:INT_MAX];
    allAttributeTypes.int64 = [NSNumber numberWithLongLong:LLONG_MAX];
    allAttributeTypes.float32 = [NSNumber numberWithFloat:FLT_MAX];
    allAttributeTypes.float64 = [NSNumber numberWithDouble:DBL_MAX];
    allAttributeTypes.string = @"xyzzy";
    allAttributeTypes.boolean = [NSNumber numberWithBool:YES];
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
    
    XCTAssertEqualObjects([NSNumber numberWithShort:SHRT_MAX], allAttributeTypes.int16);
    XCTAssertEqualObjects([NSNumber numberWithInt:INT_MAX], allAttributeTypes.int32);
    XCTAssertEqualObjects([NSNumber numberWithLongLong:LLONG_MAX], allAttributeTypes.int64);
    XCTAssertEqualObjects([NSNumber numberWithFloat:FLT_MAX], allAttributeTypes.float32);
    XCTAssertEqualObjects([NSNumber numberWithDouble:DBL_MAX], allAttributeTypes.float64);
    XCTAssertEqualObjects(@"xyzzy", allAttributeTypes.string);
    XCTAssertEqualObjects([NSNumber numberWithBool:YES], allAttributeTypes.boolean);
    XCTAssertEqualObjects([NSDate dateWithTimeIntervalSinceReferenceDate:123.0], allAttributeTypes.date);
}

@end
