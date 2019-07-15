// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWAbstractContent.h>

@class NSLock;
@class OFInvocation, OFMessageQueue;
@class OWCursor;

@interface OWStream : OWAbstractContent <OWConcreteCacheEntry>
{
    NSLock *_lock;  // protects issuedCursorsCount
    int issuedCursorsCount;
}

// Writers call these.
- (void)dataEnd;
- (void)dataAbort;

// Readers call these.
- (id)createCursor;

- (BOOL)endOfData;
- (void)waitForDataEnd;
// - (void)scheduleInvocationAtEOF:(OFInvocation *)anInvocation inQueue:(OFMessageQueue *)aQueue;

// Refugees from the OWContent protocol.
- (BOOL)contentIsValid;

// Indicates the number of cursors currently reading from this stream
- (int)cursorCount;

@end


@interface OWStream (Private)
// Private methods called by concrete OWCursor subclasses
- (void)_adjustCursorCount:(int)one;
- (BOOL)_checkForAvailableIndex:(NSUInteger)position orInvoke:(OFInvocation *)anInvocation;
@end
