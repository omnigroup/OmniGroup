// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

#import <OmniDataObjects/ODOPredicate.h> // For target-specific setup

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class ODOEntity;

@interface ODOFetchRequest : NSObject

@property (nonatomic, nullable, strong) ODOEntity *entity;
@property (nonatomic, nullable, copy) NSPredicate *predicate;
@property (nonatomic, nullable, copy) NSArray *sortDescriptors;
@property (nonatomic, nullable, copy) NSString *reason;

@end

NS_ASSUME_NONNULL_END
