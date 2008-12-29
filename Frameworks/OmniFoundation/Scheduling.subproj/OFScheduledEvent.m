// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFScheduledEvent.h>

#import <OmniFoundation/OFInvocation.h>

RCS_ID("$Id$")

@implementation OFScheduledEvent

static Class myClass;

+ (void)initialize;
{
    OBINITIALIZE;
    myClass = self;
}

- initWithInvocation:(OFInvocation *)anInvocation atDate:(NSDate *)aDate fireOnTermination:(BOOL)shouldFireOnTermination;
{
    invocation = [anInvocation retain];
    date = [aDate retain];
    fireOnTermination = shouldFireOnTermination;
    return self;
}

- initWithInvocation:(OFInvocation *)anInvocation atDate:(NSDate *)aDate;
{
    return [self initWithInvocation:anInvocation atDate:aDate fireOnTermination:NO];
}

- initForObject:(id)anObject selector:(SEL)aSelector withObject:(id)aWithObject atDate:(NSDate *)aDate;
{
    OFInvocation *anInvocation;
    OFScheduledEvent *newEvent;

    anInvocation = [[OFInvocation alloc] initForObject:anObject selector:aSelector withObject:aWithObject];
    newEvent = [self initWithInvocation:anInvocation atDate:aDate];
    [anInvocation release];
    return newEvent;
}

- (void)dealloc;
{
    [invocation release];
    [date release];
    [super dealloc];
}

- (OFInvocation *)invocation;
{
    return [[invocation retain] autorelease];
}

- (NSDate *)date;
{
    return [[date retain] autorelease];
}

- (BOOL) fireOnTermination;
{
    return fireOnTermination;
}

- (void)invoke;
{
    [invocation invoke];
}

- (NSComparisonResult)compare:(OFScheduledEvent *)otherObject;
{
    if (![otherObject isKindOfClass:[self class]])
	return NSOrderedAscending;
    OFScheduledEvent *otherEvent = otherObject;
    
    switch ([date compare:otherEvent->date]) {
        case NSOrderedAscending:
            return NSOrderedAscending;
        case NSOrderedDescending:
            return NSOrderedDescending;
        default:
        case NSOrderedSame:
            if (invocation == otherEvent->invocation)
                return NSOrderedSame;
            else if (invocation < otherEvent->invocation)
                return NSOrderedAscending;
            else
                return NSOrderedDescending;
    }
}

- (NSUInteger)hash;
{
    return [invocation hash];
}

- (BOOL)isEqual:(id)anObject;
{
    OFScheduledEvent *otherEvent;

    otherEvent = anObject;
    if (otherEvent == self)
	return YES;
    if (otherEvent->isa != myClass)
	return NO;
    return [invocation isEqual:otherEvent->invocation] && [date isEqual:otherEvent->date];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:invocation forKey:@"invocation"];
    [debugDictionary setObject:date forKey:@"date"];
    [debugDictionary setObject:fireOnTermination ? @"YES" : @"NO" forKey:@"fireOnTermination"];

    return debugDictionary;
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"%@: %@", [date description], [invocation shortDescription]];
}

@end
