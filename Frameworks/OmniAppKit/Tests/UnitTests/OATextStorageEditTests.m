// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
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

- (void)textStorageDidProcessEditing:(NSNotification *)notification;
{
    STAssertEquals([notification object], _textStorage, nil);
    _processEditingCalls++;
}

- (void)testStartingState;
{
    STAssertEquals(_processEditingCalls, 0, nil);
    OAAssertNoPendingTextStorageEdits(_textStorage);
}

- (void)testProcessEditingCalledOnUnWrappedEditing;
{
    // The header for -edited:range:changeInLength: says that it will call -processEditing if there is no unmatched -beginEditing.
    [_textStorage replaceCharactersInRange:NSMakeRange(0,0) withString:@"1"];
    STAssertEquals(_processEditingCalls, 1, nil);
    
    // Once -processEditing has been called, there should be no pending edits.
    OAAssertNoPendingTextStorageEdits(_textStorage);
}

- (void)testProcessEditingDelayedByBeginEditing;
{
    // This should batch up changes w/o sending -processEditing
    [_textStorage beginEditing];
    [_textStorage replaceCharactersInRange:NSMakeRange(0,0) withString:@"1"];

    STAssertTrue([_textStorage editedMask] == NSTextStorageEditedCharacters, nil);
    STAssertTrue([_textStorage changeInLength] == 1, nil);
    STAssertTrue(NSEqualRanges([_textStorage editedRange], NSMakeRange(0, 1)), nil);
    STAssertTrue(_processEditingCalls == 0, nil);
    
    [_textStorage endEditing];
    
    // The -endEditing should have done it.
    STAssertTrue(_processEditingCalls == 1, nil);
    OAAssertNoPendingTextStorageEdits(_textStorage);
}

- (void)testNestedProcessEditing;
{
    [_textStorage beginEditing];
    [_textStorage beginEditing];

    [_textStorage replaceCharactersInRange:NSMakeRange(0,0) withString:@"1"];
    STAssertTrue(_processEditingCalls == 0, nil);

    [_textStorage endEditing];
    STAssertTrue(_processEditingCalls == 0, nil); // ... wait for it ...

    [_textStorage endEditing];
    STAssertTrue(_processEditingCalls == 1, nil);
    OAAssertNoPendingTextStorageEdits(_textStorage);
}

// Test each of the mutators to see that they call -edited:range:changeInLength:.

- (void)testUnwrappedReplaceCharactersInRangeWithString;
{
    [_textStorage replaceCharactersInRange:NSMakeRange(0,0) withString:@"1"];
    STAssertTrue(_processEditingCalls == 1, nil);
}

- (void)testUnwrappedSetAttributesRange;
{
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:@"value", @"name", nil];
    [_textStorage setAttributes:attributes range:NSMakeRange(0, 1)];
    STAssertTrue(_processEditingCalls == 1, nil);
}

- (void)testUnwrappedMutableString;
{
    // Documentation claims that changes to this string will be tracked!
    [[_textStorage mutableString] appendString:@"y"];
    STAssertTrue(_processEditingCalls == 1, nil);
}

- (void)testUnwrappedAddAttributeValueRange;
{
    [_textStorage addAttribute:@"x" value:@"y" range:NSMakeRange(0, 1)];
    STAssertTrue(_processEditingCalls == 1, nil);
}

- (void)testUnwrappedAddAttributesRange;
{
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:@"value", @"name", nil];
    [_textStorage addAttributes:attributes range:NSMakeRange(0, 1)];
    STAssertTrue(_processEditingCalls == 1, nil);
}

- (void)testUnwrappedRemoveAttributeRange;
{
    [_textStorage removeAttribute:Attribute1 range:NSMakeRange(0, 1)];
    STAssertTrue(_processEditingCalls == 1, nil);
}

- (void)testUnwrappedReplaceCharactersInRangeWithAttributedString;
{
    NSAttributedString *prepend = [[[NSAttributedString alloc] initWithString:@"b" attributes:nil] autorelease];
    [_textStorage replaceCharactersInRange:NSMakeRange(0, 0) withAttributedString:prepend];
    STAssertTrue(_processEditingCalls == 1, nil);
}

- (void)testUnwrappedInsertAttributedStringAtIndex;
{
    NSAttributedString *prepend = [[[NSAttributedString alloc] initWithString:@"b" attributes:nil] autorelease];
    [_textStorage insertAttributedString:prepend atIndex:0];
    STAssertTrue(_processEditingCalls == 1, nil);
}

- (void)testUnwrappedAppendAttributedString;
{
    NSAttributedString *append = [[[NSAttributedString alloc] initWithString:@"b" attributes:nil] autorelease];
    [_textStorage appendAttributedString:append];
    STAssertTrue(_processEditingCalls == 1, nil);
}

- (void)testUnwrappedDeleteCharactersInRange;
{
    [_textStorage deleteCharactersInRange:NSMakeRange(0, 1)];
    STAssertTrue(_processEditingCalls == 1, nil);
}

- (void)testUnwrappedSetAttributedString;
{
    NSAttributedString *set = [[[NSAttributedString alloc] initWithString:@"b" attributes:nil] autorelease];
    [_textStorage setAttributedString:set];
    STAssertTrue(_processEditingCalls == 1, nil);
}

@end
