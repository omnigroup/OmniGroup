// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
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

@interface OATextStorageEditTests : OATestCase <NSTextStorageDelegate>
@end

static NSString * const Attribute1 = @"1";

@implementation OATextStorageEditTests
{
    NSTextStorage *_textStorage;
    int _processEditingCalls;
}


- (void)setUp;
{
    [super setUp];
    
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:@"value", Attribute1, nil];

    _processEditingCalls = 0;
    _textStorage = [[NSTextStorage alloc] initWithString:@"x" attributes:attributes];
    _textStorage.delegate = self;
}

- (void)tearDown;
{
    [super tearDown];

    _textStorage.delegate = nil;
    [_textStorage release];
    _textStorage = nil;
}

- (void)textStorage:(NSTextStorage *)textStorage didProcessEditing:(NSTextStorageEditActions)editedMask range:(NSRange)editedRange changeInLength:(NSInteger)delta;
{
    XCTAssertEqual(textStorage, _textStorage);
    _processEditingCalls++;
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
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // Radar 21551117: -[NSTextStorage addAttributes:range:] incorrectly sends two NSTextStorageDidProcessEditingNotification notifications
    XCTAssertEqual(_processEditingCalls, 2);
#else
    XCTAssertEqual(_processEditingCalls, 1);
#endif
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

@end
