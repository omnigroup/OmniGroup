// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
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

RCS_ID("$Id$")

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

- (id)createCursor;
{
    return [[[self class] alloc] initFromCursor:self];
}

//

- (NSUInteger)seekToOffset:(NSInteger)offset fromPosition:(OWCursorSeekPosition)position;
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
    abortException = anException;
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
