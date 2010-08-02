// Copyright 2010 Omni Development, Inc.  All rights reserved.
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
+ (Class)textStorageClass;
@end
@implementation OATextStorageMergedEditTests

+ (id)defaultTestSuite;
{
    if (self == [OATextStorageMergedEditTests class])
        return nil; // abstract class
    return [super defaultTestSuite];
}

+ (Class)textStorageClass;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#define STARTING_LENGTH(n) OATextStorage *ts = [[[[[self class] textStorageClass] alloc] initWithString:_spacesOfLength(n) attributes:nil] autorelease]; NSUInteger attrIndex __attribute__((unused)) = 0
#define REPLACE(position, length, replaceLength) [ts replaceCharactersInRange:NSMakeRange((position), (length)) withString:_spacesOfLength(replaceLength)]
#define SET_ATTRS(position, length) [ts setAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:attrIndex++], @"i", nil] range:NSMakeRange((position),(length))]
#define BEGIN_EDITS [ts beginEditing]
#define END_EDITS [ts endEditing]
#define CHECK_MASK(m) STAssertEquals([ts editedMask], (NSUInteger)(m), nil);
#define CHECK_RANGE(pos,len) STAssertEquals([ts editedRange], NSMakeRange((pos), (len)), nil);
#define CHECK_DELTA(delta) STAssertEquals([ts changeInLength], (NSInteger)(delta), nil)

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

    CHECK_MASK(OATextStorageEditedCharacters);
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
    
    CHECK_MASK(OATextStorageEditedCharacters);
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


// Test the real text storage if we have it.
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
@interface OATextStorageMergedEditTestsCocoa : OATextStorageMergedEditTests
@end
@implementation OATextStorageMergedEditTestsCocoa
+ (Class)textStorageClass;
{
    return [NSTextStorage class];
}
@end
#endif

// Always test our generic replacement
@interface OATextStorageMergedEditTestsGeneric : OATextStorageMergedEditTests
@end
@implementation OATextStorageMergedEditTestsGeneric
+ (Class)textStorageClass;
{
    return [OATextStorage_ class];
}
@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
// Generator for editRange tests
@interface OATextStorageMergedEditTestGenerator : OATestCase
@end

@implementation OATextStorageMergedEditTestGenerator

- (void)testRandomMergedEdit;
{
#define CHECK_SAME do { \
    STAssertEquals([realTextStorage editedMask], [fakeTextStorage editedMask], nil); \
    STAssertEquals([realTextStorage editedRange], [fakeTextStorage editedRange], nil); \
    STAssertEquals([realTextStorage changeInLength], [fakeTextStorage changeInLength], nil); \
} while (0)
    
    [self raiseAfterFailure];
    
    OFRandomState *state = OFRandomStateCreate();
    NSUInteger tries = 1000;
    
    while (tries--) {
        NSLog(@"try:");
        
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        NSUInteger startingLength = OFRandomNextState32(state) % 5;
        NSLog(@"  startingLength: %ld", startingLength);
        
        NSString *str = _spacesOfLength(startingLength);
        NSTextStorage *realTextStorage = [[[NSTextStorage alloc] initWithString:str attributes:nil] autorelease];
        OATextStorage_ *fakeTextStorage = [[[OATextStorage_ alloc] initWithString:str attributes:nil] autorelease];
        OAAssertNoPendingTextStorageEdits(realTextStorage);
        OAAssertNoPendingTextStorageEdits(fakeTextStorage);
        CHECK_SAME;
        
        [realTextStorage beginEditing];
        [fakeTextStorage beginEditing];
        
        NSUInteger operations = OFRandomNextState32(state) % 6;
        while (operations--) {
            NSUInteger operation = OFRandomNextState32(state) % 2;
            
            NSUInteger currentLength = [realTextStorage length];
            NSUInteger editLocation = (currentLength > 0) ? OFRandomNextState32(state) % currentLength : 0;
            NSUInteger lengthAfterEditLocation = currentLength - editLocation;
            NSUInteger lengthToEdit = (lengthAfterEditLocation > 0) ? OFRandomNextState32(state) % lengthAfterEditLocation : 0;
            NSRange editRange = NSMakeRange(editLocation, lengthToEdit);
            
            if (operation == 0) {
                // Replace some characters. We're assuming that replacing spaces with spaces won't ignore the edit.
                
                NSUInteger lengthToFillIn = OFRandomNextState32(state) % 5;
                NSString *replacementString = _spacesOfLength(lengthToFillIn);
                
                NSLog(@"  replace range %@ with string of length %ld", NSStringFromRange(editRange), lengthToFillIn);
                [realTextStorage replaceCharactersInRange:editRange withString:replacementString];
                [fakeTextStorage replaceCharactersInRange:editRange withString:replacementString];
                CHECK_SAME;
            } else {
                // Set some attributes
                
                NSLog(@"  set attributes on range %@", NSStringFromRange(editRange));
                NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:operation], @"i", nil];
                [realTextStorage setAttributes:attributes range:editRange];
                [fakeTextStorage setAttributes:attributes range:editRange];
                CHECK_SAME;
            }
        }
        
        [realTextStorage endEditing];
        [fakeTextStorage endEditing];
        CHECK_SAME;
        
        [pool drain];
    }
    
#undef CHECK_SAME
}

@end
#endif
