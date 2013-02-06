// Copyright 2010-2011, 2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFDynamicStoreListenerPrivate.h"

RCS_ID("$Id$");

@implementation _OFDynamicStoreListenerObserverInfo

- (id)initWithObserver:(id)observer selector:(SEL)selector key:(NSString *)key;
{
    OBPRECONDITION(observer);
    OBPRECONDITION(selector);
    OBPRECONDITION(key);
    
    self = [super init];
    if (!self)
        return nil;
        
    _nonretainedObserver = observer;
    _selector = selector;
    _key = [key copy];
    
    return self;    
}

- (void)dealloc;
{
    [_key release];
    [super dealloc];
}

- (NSUInteger)hash;
{
    return [_nonretainedObserver hash] ^ [NSStringFromSelector(_selector) hash] ^ [_key hash];
}

- (BOOL)isEqual:(id)object;
{
    if (self == object)
        return YES;
        
    if (![object isKindOfClass:[self class]])
        return NO;
        
    if (_nonretainedObserver != [object observer])
        return NO;

    if (_selector != [object selector])
        return NO;

    if (![_key isEqualToString:[object key]])
        return NO;
        
    return YES;     
}

- (id)observer;
{
    return _nonretainedObserver;
}

- (SEL)selector;
{
    return _selector;
}

- (NSString *)key;
{
    return _key;
}

@end
