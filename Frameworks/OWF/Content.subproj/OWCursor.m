// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWCursor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

static NSException *userAbortException;

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Content.subproj/OWCursor.m 68913 2005-10-03 19:36:19Z kc $")

@implementation OWCursor

+ (void)initialize;
{
    OBINITIALIZE;

    userAbortException = [[NSException alloc] initWithName:@"UserAbort" reason:NSLocalizedStringFromTableInBundle(@"User Stopped", @"OWF", [OWCursor bundle], @"cursor error") userInfo:nil];
}

- (id)initFromCursor:(id)aCursor;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)dealloc;
{
    [abortException release];
    [super dealloc];
}

- (id)newCursor;
{
    return [[[[self class] alloc] initFromCursor:self] autorelease];
}

//

- (unsigned int)seekToOffset:(int)offset fromPosition:(OWCursorSeekPosition)position;
{
    return 0;
}

- (BOOL)isAtEOF;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)abortWithException:(NSException *)anException;
{
    if (abortException == anException)
	return;
    [abortException autorelease];
    abortException = [anException retain];
}

- (void)abort;
{
    [self abortWithException:userAbortException];
}

//

- (void)scheduleInQueue:(OFMessageQueue *)aQueue invocation:(OFInvocation *)anInvocation
{
    OBRequestConcreteImplementation(self, _cmd);
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    if (abortException)
	[debugDictionary setObject:abortException forKey:@"abortException"];

    return debugDictionary;
}

@end
