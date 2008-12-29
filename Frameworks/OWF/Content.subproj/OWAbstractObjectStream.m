// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
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

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Content.subproj/OWAbstractObjectStream.m 68913 2005-10-03 19:36:19Z kc $")

@implementation OWAbstractObjectStream

- (void)writeObject:(id)anObject
{
    [self doesNotRecognizeSelector:_cmd];
}

- (void)writeFormat:(NSString *)formatString, ...;
{
    va_list argList;
    NSString *string;

    va_start(argList, formatString);
    string = [[NSString alloc] initWithFormat:formatString arguments:argList];
    [self writeObject:string];
    va_end(argList);
    [string release];
}


- (id)objectAtIndex:(unsigned int)index;
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)objectAtIndex:(unsigned int)index withHint:(void **)hint;
{
    return [self objectAtIndex:index];
}

- (unsigned int)objectCount;
{
    [self doesNotRecognizeSelector:_cmd];
    return 0;
}

- (BOOL)isIndexPastEnd:(unsigned int)anIndex;
{
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

- (id)newCursor;
{
    OWObjectStreamCursor *newCursor;
    newCursor = [[OWObjectStreamCursor alloc] initForObjectStream:self];
    [newCursor autorelease];
    return newCursor;
}


@end
