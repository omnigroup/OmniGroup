// Copyright 1997-2005, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/rcsid.h>

#import "OFTestCase.h"

RCS_ID("$Id$")

@interface OFMutableKnownKeyDictionaryTests : OFTestCase
@end

@implementation OFMutableKnownKeyDictionaryTests

static NSString * const key1 = @"key1";
static NSString * const key2 = @"key2";
static NSString * const key3 = @"key3";
static NSString * const key4 = @"key4";

static NSString * const value1 = @"value1";
static NSString * const value2 = @"value2";
static NSString * const value3 = @"value3";
static NSString * const value4 = @"value4";

static void _enumeratorShouldHaveValues(OFMutableKnownKeyDictionaryTests *self, NSEnumerator *enumerator, NSArray *expectedValues)
{
    NSMutableSet *enumeratedValues = [NSMutableSet set];

    id value;
    while ((value = [enumerator nextObject])) {
        [enumeratedValues addObject:value];
    }
    
    XCTAssertEqual([enumeratedValues count], [expectedValues count]);
    
    for (value in expectedValues)
        XCTAssertTrue([enumeratedValues containsObject:value]);
}
#define enumeratorShouldHaveValues(enumerator, values) _enumeratorShouldHaveValues(self, (enumerator), (values))

- (void)testBasic;
{
    NSArray *keys1 = [NSArray arrayWithObjects:key1, key2, key3, key4, nil];
    NSArray *keys2 = [NSArray arrayWithObjects:key1, key2, key3, nil];
    NSArray *keys3 = [NSArray arrayWithObjects:key1, nil];
    
    OFKnownKeyDictionaryTemplate *template1 = [OFKnownKeyDictionaryTemplate templateWithKeys:keys1];
    OFKnownKeyDictionaryTemplate *template2 = [OFKnownKeyDictionaryTemplate templateWithKeys:keys2];
    OFKnownKeyDictionaryTemplate *template3 = [OFKnownKeyDictionaryTemplate templateWithKeys:keys3];

    XCTAssertTrue(template1 != template2);
    XCTAssertTrue(template1 != template3);
    
    OFMutableKnownKeyDictionary *dict1 = [OFMutableKnownKeyDictionary newWithTemplate:template1];
    OFMutableKnownKeyDictionary *dict2 = [OFMutableKnownKeyDictionary newWithTemplate:template2];
    OFMutableKnownKeyDictionary *dict3 = [OFMutableKnownKeyDictionary newWithTemplate:template3];

    XCTAssertEqual([dict1 count], 0ULL);
    XCTAssertEqual([dict2 count], 0ULL);
    XCTAssertEqual([dict3 count], 0ULL);
    
    [dict1 setObject:value1 forKey:key1];
    XCTAssertEqual([dict1 count], 1ULL);
    XCTAssertEqualObjects(dict1[key1], value1);
    XCTAssertNil(dict1[key2]);
    XCTAssertNil(dict1[key3]);
    
    [dict1 setObject:value2 forKey:key2];
    XCTAssertEqual([dict1 count], 2ULL);
    XCTAssertEqualObjects(dict1[key1], value1);
    XCTAssertEqualObjects(dict1[key2], value2);
    XCTAssertNil(dict1[key3]);

    [dict1 setObject:value3 forKey:key3];
    [dict1 setObject:value4 forKey:key4];
    XCTAssertEqual([dict1 count], 4ULL);
    XCTAssertEqualObjects(dict1[key1], value1);
    XCTAssertEqualObjects(dict1[key2], value2);
    XCTAssertEqualObjects(dict1[key3], value3);
    XCTAssertEqualObjects(dict1[key4], value4);

    
    XCTAssertEqualObjects([dict1 objectForKey:[NSString stringWithCString:"key1" encoding:NSASCIIStringEncoding]], value1, @"non pointer-equal keys should work");
    
    XCTAssertThrows([dict1 setObject: @"bogus" forKey: @"bogus"], @"Setting unknown keys should raise");
    
    enumeratorShouldHaveValues([[dict1 allKeys] objectEnumerator], (@[key1, key2, key3, key4]));
    enumeratorShouldHaveValues([[dict1 allValues] objectEnumerator], (@[value1, value2, value3, value4]));
    
    enumeratorShouldHaveValues([dict1 keyEnumerator], (@[key1, key2, key3, key4]));
    enumeratorShouldHaveValues([dict1 objectEnumerator], (@[value1, value2, value3, value4]));
    
    [dict1 removeObjectForKey:key1];
    enumeratorShouldHaveValues([dict1 keyEnumerator], (@[key2, key3, key4]));
    enumeratorShouldHaveValues([dict1 objectEnumerator], (@[value2, value3, value4]));
    
    [dict1 removeObjectForKey:key3];
    [dict1 removeObjectForKey:key4];
    enumeratorShouldHaveValues([dict1 keyEnumerator], (@[key2]));
    enumeratorShouldHaveValues([dict1 objectEnumerator], (@[value2]));
    
    [dict1 removeObjectForKey:key2];
    [dict1 removeObjectForKey:key2];
    enumeratorShouldHaveValues([dict1 keyEnumerator], (@[]));
    enumeratorShouldHaveValues([dict1 objectEnumerator], (@[]));
}

@end
