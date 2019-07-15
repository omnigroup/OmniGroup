// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSPredicate.h>
#import <Foundation/NSExpression.h>

NS_ASSUME_NONNULL_BEGIN

extern NSMutableArray * ODOFilteredArrayUsingPredicate(NSArray *array, NSPredicate *predicate);
extern NSUInteger ODOCountInArrayMatchingPredicate(NSArray *array, NSPredicate *predicate);

NS_ASSUME_NONNULL_END
