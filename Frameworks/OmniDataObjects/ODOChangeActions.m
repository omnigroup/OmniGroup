// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOChangeActions.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation ODOChangeActions
{
    NSMutableArray <ODOObjectPropertyChangeAction> *_actions;
}

- init;
{
    self = [super init];
    _actions = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc;
{
    [_actions release];
    [super dealloc];
}

- (void)append:(ODOObjectPropertyChangeAction)action;
{
    [_actions addObject:[[action copy] autorelease]];
}

- (void)prepend:(ODOObjectPropertyChangeAction)action;
{
    [_actions insertObject:[[action copy] autorelease] atIndex:0];
}

@end

@implementation ODOObjectSetDefaultAttributeValueActions
{
    NSMutableArray <ODOObjectSetDefaultAttributeValues> *_actions;
}

- init;
{
    self = [super init];
    _actions = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc;
{
    [_actions release];
    [super dealloc];
}

- (void)addAction:(ODOObjectSetDefaultAttributeValues)action;
{
    [_actions addObject:[[action copy] autorelease]];
}

@end

NS_ASSUME_NONNULL_END
