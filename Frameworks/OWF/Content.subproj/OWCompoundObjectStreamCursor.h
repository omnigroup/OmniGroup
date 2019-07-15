// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWCursor.h>

@class NSMutableArray;

@interface OWCompoundObjectStreamCursor : OWCursor <NSCopying>
{
    NSMutableArray *cursors;
    int cursorIndex;
}

// Both of these call [super initFromCursor].
- initFromCursor:(id)aCursor;
- initFromCursor:(id)aCursor andCursor:(id)anotherCursor;

- (id)readObject;
- (void)skipObjects:(int)count;
- (void)ungetObject:(id)anObject;

// These hold on to and modify the cursor they are given.
- (void)appendCursor:(OWCursor *)appendedCursor;
- (void)prependCursor:(OWCursor *)prependedCursor;

@end
