// Copyright 2010, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OATestCase.h"

#import <OmniAppKit/OATextStorage.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

// +[NSString spacesOfLength:] isn't included in our iOS static library and we don't need to do so just for this.
static NSString *_stringOfLength(unichar c, NSUInteger length)
{
    unichar *str = malloc(sizeof(*str) * length);
    for (NSUInteger characterIndex = 0; characterIndex < length; characterIndex++)
        str[characterIndex] = c;
    return [[[NSString alloc] initWithCharactersNoCopy:str length:length freeWhenDone:YES] autorelease];
}
static NSString *_spacesOfLength(NSUInteger length)
{
    return _stringOfLength(' ', length);
}

@interface OATextStorageMergedEditTests : OATestCase
@end
@implementation OATextStorageMergedEditTests

#define STARTING_LENGTH(n) NSTextStorage *ts = [[[NSTextStorage alloc] initWithString:_spacesOfLength(n) attributes:nil] autorelease]; NSUInteger attrIndex __attribute__((unused)) = 0
#define REPLACE(position, length, replaceLength) [ts replaceCharactersInRange:NSMakeRange((position), (length)) withString:_spacesOfLength(replaceLength)]
#define SET_ATTRS(position, length) [ts setAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:attrIndex++], @"i", nil] range:NSMakeRange((position),(length))]
#define BEGIN_EDITS [ts beginEditing]
#define END_EDITS [ts endEditing]
#define CHECK_MASK(m) XCTAssertEqual([ts editedMask], (NSUInteger)(m))
#define CHECK_RANGE(pos,len) XCTAssertTrue(NSEqualRanges([ts editedRange], NSMakeRange((pos), (len))))
#define CHECK_DELTA(delta) XCTAssertEqual([ts changeInLength], (NSInteger)(delta))

- (void)test0;
{
    STARTING_LENGTH(1);
    BEGIN_EDITS;

    SET_ATTRS(0, 0);

    CHECK_MASK(0);
    CHECK_RANGE(NSNotFound, 1);
    CHECK_DELTA(0);
    END_EDITS;
}

- (void)test1;
{
    STARTING_LENGTH(2);
    BEGIN_EDITS;
    
    REPLACE(0, 0, 0);
    REPLACE(0, 1, 3);

    CHECK_MASK(NSTextStorageEditedCharacters);
    CHECK_RANGE(0, 3);
    CHECK_DELTA(2); // Was 2. Replaced 1 of those with 3.
    END_EDITS;
}

- (void)test2;
{
    STARTING_LENGTH(2);
    BEGIN_EDITS;
    
    REPLACE(0, 1, 2);
    REPLACE(1, 1, 0);
    
    CHECK_MASK(NSTextStorageEditedCharacters);
    CHECK_RANGE(0, 1);
    CHECK_DELTA(0);
    END_EDITS;
}

- (void)test3;
{
    STARTING_LENGTH(0);
    BEGIN_EDITS;
    
    SET_ATTRS(0, 0);
    REPLACE(0, 0, 0);
    
    CHECK_MASK(2);
    CHECK_RANGE(0, 0);
    CHECK_DELTA(0);
    END_EDITS;
}

@end
