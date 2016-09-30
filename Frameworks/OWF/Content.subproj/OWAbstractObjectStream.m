// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWAbstractObjectStream.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWObjectStreamCursor.h>

RCS_ID("$Id$")

@implementation OWAbstractObjectStream

- (void)writeObject:(id)anObject
{
    [self doesNotRecognizeSelector:_cmd];
}

- (void)writeFormat:(NSString *)formatString, ...;
{
    va_list argList;
    va_start(argList, formatString);
    NSString *string = [[NSString alloc] initWithFormat:formatString arguments:argList];
    [self writeObject:string];
    va_end(argList);
}


- (id)objectAtIndex:(NSUInteger)index;
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)objectAtIndex:(NSUInteger)index withHint:(void **)hint;
{
    return [self objectAtIndex:index];
}

- (NSUInteger)objectCount;
{
    [self doesNotRecognizeSelector:_cmd];
    return 0;
}

- (BOOL)isIndexPastEnd:(NSUInteger)anIndex;
{
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

- (id)createCursor;
{
    OWObjectStreamCursor *newCursor = [[OWObjectStreamCursor alloc] initForObjectStream:self];
    return newCursor;
}


@end
