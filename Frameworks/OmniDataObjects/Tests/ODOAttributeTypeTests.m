// Copyright 2008 Omni Development, Inc.  All rights reserved.
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
    ODOObject *allAttributeTypes = [[ODOObject alloc] initWithEditingContext:_editingContext entity:[ODOTestCaseModel() entityNamed:@"AllAttributeTypes"] primaryKey:nil];
    [_editingContext insertObject:allAttributeTypes];
    [allAttributeTypes release];

    // TODO: We don't currently define any saturation modes for scalar attributes.  We can either be strict and error out or we could be more flexible like SQLite is (though we'd have to bind all ints via the 64-bit path).
    [allAttributeTypes setValue:[NSNumber numberWithShort:SHRT_MAX] forKey:@"int16"];
    [allAttributeTypes setValue:[NSNumber numberWithInt:INT_MAX] forKey:@"int32"];
    [allAttributeTypes setValue:[NSNumber numberWithLongLong:LLONG_MAX] forKey:@"int64"];
    [allAttributeTypes setValue:[NSNumber numberWithFloat:FLT_MAX] forKey:@"float32"];
    [allAttributeTypes setValue:[NSNumber numberWithDouble:DBL_MAX] forKey:@"float64"];
    [allAttributeTypes setValue:@"xyzzy" forKey:@"string"];
    [allAttributeTypes setValue:[NSNumber numberWithBool:YES] forKey:@"boolean"];
    [allAttributeTypes setValue:[NSDate dateWithTimeIntervalSinceReferenceDate:123.0] forKey:@"date"];
    
    unsigned char bytes[4] = {0xde, 0xad, 0xbe, 0xef};
    [allAttributeTypes setValue:[NSData dataWithBytes:bytes length:sizeof(bytes)] forKey:@"data"];
    
    NSError *error = nil;
    OBShouldNotError([_editingContext saveWithDate:[NSDate date] error:&error]);
    
    ODOObjectID *objectID = [[[allAttributeTypes objectID] retain] autorelease];
    
    // Refetch the object
    [_editingContext reset];
    
    allAttributeTypes = [_editingContext fetchObjectWithObjectID:objectID error:&error];
    OBShouldNotError(allAttributeTypes != nil);
    
    shouldBeEqual([NSNumber numberWithShort:SHRT_MAX], [allAttributeTypes valueForKey:@"int16"]);
    shouldBeEqual([NSNumber numberWithInt:INT_MAX], [allAttributeTypes valueForKey:@"int32"]);
    shouldBeEqual([NSNumber numberWithLongLong:LLONG_MAX], [allAttributeTypes valueForKey:@"int64"]);
    shouldBeEqual([NSNumber numberWithFloat:FLT_MAX], [allAttributeTypes valueForKey:@"float32"]);
    shouldBeEqual([NSNumber numberWithDouble:DBL_MAX], [allAttributeTypes valueForKey:@"float64"]);
    shouldBeEqual(@"xyzzy", [allAttributeTypes valueForKey:@"string"]);
    shouldBeEqual([NSNumber numberWithBool:YES], [allAttributeTypes valueForKey:@"boolean"]);
    shouldBeEqual([NSDate dateWithTimeIntervalSinceReferenceDate:123.0], [allAttributeTypes valueForKey:@"date"]);
}

@end
