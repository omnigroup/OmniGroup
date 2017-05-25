// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOPredicate.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

NSMutableArray * ODOFilteredArrayUsingPredicate(NSArray *array, NSPredicate *predicate)
{
    OBPRECONDITION(predicate); // nil predicate typically means unqualified; do we need to implement that case?

    NSMutableArray *result = [NSMutableArray array];
    for (id object in array) {
        if ([predicate evaluateWithObject:object]) {
	    [result addObject:object];
        }
    }
    return result;
}

NSUInteger ODOCountInArrayMatchingPredicate(NSArray *array, NSPredicate *predicate)
{
    OBPRECONDITION(predicate); // nil predicate typically means unqualified; do we need to implement that case?
    NSUInteger matches = 0;
    for (id object in array) {
        if ([predicate evaluateWithObject:object]) {
            matches++;
        }
    }
    return matches;
}

NS_ASSUME_NONNULL_END
