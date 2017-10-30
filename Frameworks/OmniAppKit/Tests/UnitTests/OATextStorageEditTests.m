// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OATestCase.h"

#import <OmniAppKit/OATextStorage.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

// The documentation for -edited:range:changeInLength: claims that it must be called by the primitives. Let's check that AppKit does this.
// The documentation/headers also disagree on when -processEditing gets called. Let's test that too.
// We'll then be able to use this as a reference for writing OATextStorage for use on iOS.

@interface OATextStorageEditTests : OATestCase <OATextStorageDelegate>
{
@private
    OATextStorage *_textStorage;
    int _processEditingCalls;
}

+ (Class)textStorageClass;

@end

static NSString * const Attribute1 = @"1";

typedef struct {
    OATextStorageEditActions editedMask;
    NSRange editedRange;
    NSInteger changeInLength;
} DelegateState;

@implementation OATextStorageEditTests
{
    NSUInteger _lastOrdering;

    NSUInteger _delegateWillOrdering;
    NSUInteger _delegateDidOrdering;
    NSUInteger _notificationWillOrdering;
    NSUInteger _notificationDidOrdering;

    DelegateState _delegateWillState;
    DelegateState _delegateDidState;
}

+ (id)defaultTestSuite;
{
    if (self == [OATextStorageEditTests class])
        return [[[XCTestSuite alloc] initWithName:@"OATextStorageEditTests"] autorelease]; // abstract class
    return [super defaultTestSuite];
}

+ (Class)textStorageClass;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)setUp;
{
    [super setUp];
    
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:@"value", Attribute1, nil];

    Class textStorageClass = [[self class] textStorageClass];

    _processEditingCalls = 0;
    _textStorage = [[textStorageClass alloc] initWithString:@"x" attributes:attributes];
    _textStorage.delegate = self;

    _delegateDidState = (DelegateState){0};
    _delegateDidState = (DelegateState){0};
}

- (void)tearDown;
{
    [super tearDown];

    _textStorage.delegate = nil;
    [_textStorage release];
    _textStorage = nil;
}

- (void)textStorage:(OATextStorage *)textStorage willProcessEditing:(OATextStorageEditActions)editedMask range:(NSRange)editedRange changeInLength:(NSInteger)delta;
{
    _delegateWillOrdering = ++_lastOrdering;

    _delegateWillState.editedMask = editedMask;
    _delegateWillState.editedRange = editedRange;
    _delegateWillState.changeInLength = delta;
}

- (void)textStorage:(NSTextStorage *)textStorage didProcessEditing:(NSTextStorageEditActions)editedMask range:(NSRange)editedRange changeInLength:(NSInteger)delta;
{
    XCTAssertEqual(textStorage, _textStorage);
    _processEditingCalls++;

    _delegateDidOrdering = ++_lastOrdering;

    _delegateDidState.editedMask = editedMask;
    _delegateDidState.editedRange = editedRange;
    _delegateDidState.changeInLength = delta;
}

- (void)testStartingState;
{
    XCTAssertEqual(_processEditingCalls, 0);
    OAAssertNoPendingTextStorageEdits(_textStorage);
}

- (void)testProcessEditingCalledOnUnWrappedEditing;
{
    // The header for -edited:range:changeInLength: says that it will call -processEditing if there is no unmatched -beginEditing.
    [_textStorage replaceCharactersInRange:NSMakeRange(0,0) withString:@"1"];
    XCTAssertEqual(_processEditingCalls, 1);
    
    // Once -processEditing has been called, there should be no pending edits.
    OAAssertNoPendingTextStorageEdits(_textStorage);
}

- (void)testProcessEditingDelayedByBeginEditing;
{
    // This should batch up changes w/o sending -processEditing
    [_textStorage beginEditing];
    [_textStorage replaceCharactersInRange:NSMakeRange(0,0) withString:@"1"];

    XCTAssertEqual([_textStorage editedMask], NSTextStorageEditedCharacters);
    XCTAssertEqual([_textStorage changeInLength], 1L);
    XCTAssertTrue(NSEqualRanges([_textStorage editedRange], NSMakeRange(0, 1)));
    XCTAssertEqual(_processEditingCalls, 0);
    
    [_textStorage endEditing];
    
    // The -endEditing should have done it.
    XCTAssertEqual(_processEditingCalls, 1);
    OAAssertNoPendingTextStorageEdits(_textStorage);
}

- (void)testNestedProcessEditing;
{
    [_textStorage beginEditing];
    [_textStorage beginEditing];

    [_textStorage replaceCharactersInRange:NSMakeRange(0,0) withString:@"1"];
    XCTAssertEqual(_processEditingCalls, 0);

    [_textStorage endEditing];
    XCTAssertEqual(_processEditingCalls, 0); // ... wait for it ...

    [_textStorage endEditing];
    XCTAssertEqual(_processEditingCalls, 1);
    OAAssertNoPendingTextStorageEdits(_textStorage);
}

// Test each of the mutators to see that they call -edited:range:changeInLength:.

- (void)testUnwrappedReplaceCharactersInRangeWithString;
{
    [_textStorage replaceCharactersInRange:NSMakeRange(0,0) withString:@"1"];
    XCTAssertEqual(_processEditingCalls, 1);
}

- (void)testUnwrappedSetAttributesRange;
{
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:@"value", @"name", nil];
    [_textStorage setAttributes:attributes range:NSMakeRange(0, 1)];
    XCTAssertEqual(_processEditingCalls, 1);
}

- (void)testUnwrappedMutableString;
{
    // Documentation claims that changes to this string will be tracked!
    [[_textStorage mutableString] appendString:@"y"];
    XCTAssertEqual(_processEditingCalls, 1);
}

- (void)testUnwrappedAddAttributeValueRange;
{
    [_textStorage addAttribute:@"x" value:@"y" range:NSMakeRange(0, 1)];
    XCTAssertEqual(_processEditingCalls, 1);
}

- (void)testUnwrappedAddAttributesRange;
{
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:@"value", @"name", nil];
    [_textStorage addAttributes:attributes range:NSMakeRange(0, 1)];
    XCTAssertEqual(_processEditingCalls, 1);
}

- (void)testUnwrappedRemoveAttributeRange;
{
    [_textStorage removeAttribute:Attribute1 range:NSMakeRange(0, 1)];
    XCTAssertEqual(_processEditingCalls, 1);
}

- (void)testUnwrappedReplaceCharactersInRangeWithAttributedString;
{
    NSAttributedString *prepend = [[[NSAttributedString alloc] initWithString:@"b" attributes:nil] autorelease];
    [_textStorage replaceCharactersInRange:NSMakeRange(0, 0) withAttributedString:prepend];
    XCTAssertEqual(_processEditingCalls, 1);
}

- (void)testUnwrappedInsertAttributedStringAtIndex;
{
    NSAttributedString *prepend = [[[NSAttributedString alloc] initWithString:@"b" attributes:nil] autorelease];
    [_textStorage insertAttributedString:prepend atIndex:0];
    XCTAssertEqual(_processEditingCalls, 1);
}

- (void)testUnwrappedAppendAttributedString;
{
    NSAttributedString *append = [[[NSAttributedString alloc] initWithString:@"b" attributes:nil] autorelease];
    [_textStorage appendAttributedString:append];
    XCTAssertEqual(_processEditingCalls, 1);
}

- (void)testUnwrappedDeleteCharactersInRange;
{
    [_textStorage deleteCharactersInRange:NSMakeRange(0, 1)];
    XCTAssertEqual(_processEditingCalls, 1);
}

- (void)testUnwrappedSetAttributedString;
{
    NSAttributedString *set = [[[NSAttributedString alloc] initWithString:@"b" attributes:nil] autorelease];
    [_textStorage setAttributedString:set];
    XCTAssertEqual(_processEditingCalls, 1);
}

- (void)testDelegateVsNotificationTiming;
{
    NSAttributedString *empty = [[[NSAttributedString alloc] initWithString:@"" attributes:nil] autorelease];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_testDelegateVsNotificationTimingWillProcessNotification:) name:OATextStorageWillProcessEditingNotification object:_textStorage];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_testDelegateVsNotificationTimingDidProcessNotification:) name:OATextStorageDidProcessEditingNotification object:_textStorage];

    [_textStorage replaceCharactersInRange:NSMakeRange(0, 1) withAttributedString:empty];

    /*
     NSTextStorage sends these in the following order, so we should too...

     notification "will"
     delegate "will"
     notification "did"
     delegate "did"

     */
    XCTAssertEqual(_notificationWillOrdering, 1UL);
    XCTAssertEqual(_delegateWillOrdering, 2UL);
    XCTAssertEqual(_notificationDidOrdering, 3UL);
    XCTAssertEqual(_delegateDidOrdering, 4UL);

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_testDelegateVsNotificationTimingWillProcessNotification:(NSNotification *)note;
{
    _notificationWillOrdering = ++_lastOrdering;
}

- (void)_testDelegateVsNotificationTimingDidProcessNotification:(NSNotification *)note;
{
    _notificationDidOrdering = ++_lastOrdering;
}

- (void)testMoreEditsDuringProcessing;
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_testMoreEditsDuringProcessingWillProcessNotification:) name:OATextStorageWillProcessEditingNotification object:_textStorage];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_testMoreEditsDuringProcessingDidProcessNotification:) name:OATextStorageDidProcessEditingNotification object:_textStorage];

    NSDictionary *attributes = [_textStorage attributesAtIndex:0 effectiveRange:NULL];
    NSAttributedString *prepend = [[[NSAttributedString alloc] initWithString:@"b" attributes:attributes] autorelease];
    [_textStorage insertAttributedString:prepend atIndex:0];

    // The delegate 'will' gets called right after the 'will' notification and should get the same state.
    XCTAssertEqual(_delegateWillState.editedMask, OATextStorageEditedCharacters|OATextStorageEditedAttributes);
    XCTAssertTrue(NSEqualRanges(_delegateWillState.editedRange, NSMakeRange(0, 1)));
    XCTAssertEqual(_delegateWillState.changeInLength, 1L);

    // The delegate did' gets called last and should see the extra character.
    XCTAssertEqual(_delegateDidState.editedMask, OATextStorageEditedCharacters|OATextStorageEditedAttributes);
    XCTAssertTrue(NSEqualRanges(_delegateDidState.editedRange, NSMakeRange(0, 2)));
    XCTAssertEqual(_delegateDidState.changeInLength, 2L);

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_testMoreEditsDuringProcessingWillProcessNotification:(NSNotification *)note;
{
    // We had "a" and "b" was inserted at index 0 (with the notification firing first)
    XCTAssertEqual(_textStorage.editedMask, OATextStorageEditedCharacters|OATextStorageEditedAttributes); // TODO: We get both flags here...
    XCTAssertTrue(NSEqualRanges(_textStorage.editedRange, NSMakeRange(0, 1)));
    XCTAssertEqual(_textStorage.changeInLength, 1L);

    // this should apply to the 'b' that is inserted.
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:@"value", @"name", nil];
    [_textStorage addAttributes:attributes range:NSMakeRange(0, 1)];

    // Now we should have the attribute mask too, but the range and delta should be the same
    XCTAssertEqual(_textStorage.editedMask, OATextStorageEditedCharacters|OATextStorageEditedAttributes);
    XCTAssertTrue(NSEqualRanges(_textStorage.editedRange, NSMakeRange(0, 1)));
    XCTAssertEqual(_textStorage.changeInLength, 1L);
}

- (void)_testMoreEditsDuringProcessingDidProcessNotification:(NSNotification *)note;
{
    // Same as at the end of the 'will'
    XCTAssertEqual(_textStorage.editedMask, OATextStorageEditedCharacters|OATextStorageEditedAttributes);
    XCTAssertTrue(NSEqualRanges(_textStorage.editedRange, NSMakeRange(0, 1)));
    XCTAssertEqual(_textStorage.changeInLength, 1L);

    NSAttributedString *prepend = [[[NSAttributedString alloc] initWithString:@"x" attributes:nil] autorelease];
    [_textStorage insertAttributedString:prepend atIndex:0];

    // More length
    XCTAssertEqual(_textStorage.editedMask, OATextStorageEditedCharacters|OATextStorageEditedAttributes);
    XCTAssertTrue(NSEqualRanges(_textStorage.editedRange, NSMakeRange(0, 2)));
    XCTAssertEqual(_textStorage.changeInLength, 2L);
}

@end

// Test the real text storage if we have it.
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
@interface OATextStorageEditTestsCocoa : OATextStorageEditTests
@end
@implementation OATextStorageEditTestsCocoa
+ (Class)textStorageClass;
{
    return [NSTextStorage class];
}
@end
#endif

// Always test our generic replacement
@interface OATextStorageEditTestsGeneric : OATextStorageEditTests
@end
@implementation OATextStorageEditTestsGeneric
+ (Class)textStorageClass;
{
    return [OATextStorage_ class];
}
@end
