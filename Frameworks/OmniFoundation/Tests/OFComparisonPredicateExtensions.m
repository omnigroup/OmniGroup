// Copyright 2000-2008, 2010, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/NSComparisonPredicate-OFExtensions.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@protocol A
- (void)foo;
@end

@protocol B
- (void)bar;
@end

@interface OFComparisonPredicateExtensionsTarget : NSObject <A>
@end
@implementation OFComparisonPredicateExtensionsTarget
- (void)foo;
{
}
@end




@interface OFComparisonPredicateExtensions : OFTestCase
@end

@implementation OFComparisonPredicateExtensions

- (void)testIsKindOfClassPredicate;
{
    NSDictionary *dictionary = [[NSDictionary alloc] init];
    
    NSPredicate *isKindOfDictionaryPredicate = [NSComparisonPredicate isKindOfClassPredicate:[NSDictionary class]];
    XCTAssertTrue([isKindOfDictionaryPredicate evaluateWithObject:dictionary]);
    
    NSPredicate *isKindOfArrayPredicate = [NSComparisonPredicate isKindOfClassPredicate:[NSArray class]];
    XCTAssertTrue(![isKindOfArrayPredicate evaluateWithObject:dictionary]);
    
}

- (void)testConformsToProtocolPredicate;
{
    OFComparisonPredicateExtensionsTarget *target = [[OFComparisonPredicateExtensionsTarget alloc] init];
    
    NSPredicate *conformsToCodingPredicate = [NSComparisonPredicate conformsToProtocolPredicate:@protocol(A)];
    XCTAssertTrue([conformsToCodingPredicate evaluateWithObject:target]);
    
    NSPredicate *conformsToLockingPredicate = [NSComparisonPredicate conformsToProtocolPredicate:@protocol(B)];
    XCTAssertTrue(![conformsToLockingPredicate evaluateWithObject:target]);
    
}

@end
