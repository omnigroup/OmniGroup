// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSparseArray.h>

#import <OmniFoundation/OFNull.h>

RCS_ID("$Id$")

@implementation OFSparseArray

static OFNull *nullValue = nil;

+ (void)initialize;
{
    OBINITIALIZE;

    nullValue = (id)[[OFNull nullStringObject] retain];
}

- initWithCapacity:(NSUInteger)aCapacity;
{
    if (![super init])
	return nil;

    values = [[NSMutableArray alloc] initWithCapacity:aCapacity];
    valuesLength = 0;

    return self;
}

- init;
{
    return [self initWithCapacity:0];
}

- (void)dealloc;
{
    [values release];
    [defaultValue release];
    [super dealloc];
}

- (NSUInteger)count;
{
    return valuesLength;
}

- (id)objectAtIndex:(NSUInteger)anIndex;
{
    id value;

    if (anIndex >= valuesLength)
	return defaultValue;
    value = [values objectAtIndex:anIndex];
    if (value == nullValue)
	return defaultValue;
    return value;
}

static inline void setValuesLength(OFSparseArray *self, NSUInteger anIndex)
{
    while (self->valuesLength < anIndex) {
	[self->values addObject:nullValue];
	self->valuesLength++;
    }
}

- (void)setObject:(id)anObject atIndex:(NSUInteger)anIndex;
{
    if (!anObject || anObject == defaultValue)
	anObject = nullValue;
    if (anIndex < self->valuesLength) {
	[self->values replaceObjectAtIndex:anIndex withObject:anObject];
    } else if (anObject != nullValue) {
	setValuesLength(self, anIndex);
	[values addObject:anObject];
	valuesLength++;
    }
}

- (void)setDefaultValue:(id)aDefaultValue;
{
    if (defaultValue != aDefaultValue) {
	[defaultValue release];
        defaultValue = [aDefaultValue retain];
    }
}

- (NSArray *)valuesArray;
{
    return values;
}

// OBObject subclass
- (NSMutableDictionary *)debugDictionary;
{
    return (id)values;
}

@end
