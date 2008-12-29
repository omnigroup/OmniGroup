// Copyright 2000-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#if defined(MAC_OS_X_VERSION_10_4) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/NSComparisonPredicate-OFExtensions.h>

RCS_ID("$Id$")

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
    should([isKindOfDictionaryPredicate evaluateWithObject:dictionary]);
    
    NSPredicate *isKindOfArrayPredicate = [NSComparisonPredicate isKindOfClassPredicate:[NSArray class]];
    should(![isKindOfArrayPredicate evaluateWithObject:dictionary]);
    
    [dictionary release];
}

- (void)testConformsToProtocolPredicate;
{
    OFComparisonPredicateExtensionsTarget *target = [[OFComparisonPredicateExtensionsTarget alloc] init];
    
    NSPredicate *conformsToCodingPredicate = [NSComparisonPredicate conformsToProtocolPredicate:@protocol(A)];
    should([conformsToCodingPredicate evaluateWithObject:target]);
    
    NSPredicate *conformsToLockingPredicate = [NSComparisonPredicate conformsToProtocolPredicate:@protocol(B)];
    should(![conformsToLockingPredicate evaluateWithObject:target]);
    
    [target release];
}

@end

#endif
