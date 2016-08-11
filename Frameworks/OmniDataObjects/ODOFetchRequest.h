// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <OmniDataObjects/ODOPredicate.h> // For target-specific setup

@class NSArray;
@class ODOEntity;

@interface ODOFetchRequest : OFObject

@property(nonatomic,retain) ODOEntity *entity;
@property(nonatomic,copy) NSPredicate *predicate;
@property(nonatomic,copy) NSArray *sortDescriptors;
@property(nonatomic,copy) NSString *reason;

@end
