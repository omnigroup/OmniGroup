// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOFetchRequest.h>

RCS_ID("$Id$")

@implementation ODOFetchRequest

- (void)dealloc;
{
    [_entity release];
    [_predicate release];
    [_sortDescriptors release];
    [super dealloc];
}

- (void)setEntity:(ODOEntity *)entity;
{
    if (entity == _entity)
        return;
    [_entity release];
    _entity = [entity retain];
}

- (ODOEntity *)entity;
{
    return _entity;
}

- (void)setPredicate:(NSPredicate *)predicate;
{
    if (predicate == _predicate)
        return;
    [_predicate release];
    _predicate = [predicate retain];
}

- (NSPredicate *)predicate;
{
    return _predicate;
}

- (void)setSortDescriptors:(NSArray *)sortDescriptors;
{
    if (sortDescriptors == _sortDescriptors)
        return;
    [_sortDescriptors release];
    _sortDescriptors = [sortDescriptors retain];
}

- (NSArray *)sortDescriptors;
{
    return _sortDescriptors;
}

- (void)setReason:(NSString *)reason;
{
    [_reason autorelease];
    _reason = [reason copy];
}

- (NSString *)reason;
{
    return _reason;
}

@end

