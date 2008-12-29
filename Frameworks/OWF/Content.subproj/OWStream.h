// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Content.subproj/OWStream.h 68913 2005-10-03 19:36:19Z kc $

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
- (id)newCursor;

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
- (BOOL)_checkForAvailableIndex:(unsigned)position orInvoke:(OFInvocation *)anInvocation;
@end
