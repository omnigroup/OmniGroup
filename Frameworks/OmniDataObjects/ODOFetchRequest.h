// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOFetchRequest.h 104583 2008-09-06 21:23:18Z kc $

#import <OmniFoundation/OFObject.h>

#import <OmniDataObjects/ODOPredicate.h> // For target-specific setup

@class NSArray;
@class ODOEntity;

@interface ODOFetchRequest : OFObject
{
@private
    ODOEntity *_entity;
    NSPredicate *_predicate;
    NSArray *_sortDescriptors;
    NSString *_reason;
}

- (void)setEntity:(ODOEntity *)entity;
- (ODOEntity *)entity;

- (void)setPredicate:(NSPredicate *)predicate;
- (NSPredicate *)predicate;

- (void)setSortDescriptors:(NSArray *)sortDescriptors;
- (NSArray *)sortDescriptors;

- (void)setReason:(NSString *)reason;
- (NSString *)reason;

@end
