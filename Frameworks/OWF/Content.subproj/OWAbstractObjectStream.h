// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWStream.h>

@interface OWAbstractObjectStream : OWStream
{
}

- (void)writeObject:(id)anObject;
- (void)writeFormat:(NSString *)formatString, ... NS_FORMAT_FUNCTION(1,2);

- (id)objectAtIndex:(NSUInteger)index;
- (id)objectAtIndex:(NSUInteger)index withHint:(void **)hint;
- (NSUInteger)objectCount;
- (BOOL)isIndexPastEnd:(NSUInteger)index;

@end
