// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSText-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSTextStorage-OAExtensions.h>

RCS_ID("$Id$")

@implementation NSText (OAExtensions)

- (IBAction)jumpToSelection:(id)sender;
{
    [self scrollRangeToVisible:[self selectedRange]];
}

- (unsigned int)textLength;
{
    return [[self string] length];
}

- (void)appendTextString:(NSString *)string;
{
    NSRange endRange;

    if ([NSString isEmptyString:string])
	return;
    endRange = NSMakeRange([self textLength], 0);
    [self replaceCharactersInRange:endRange withString:string];
}

- (void)appendRTFData:(NSData *)data;
{
    NSRange endRange;

    if (data == nil || [data length] == 0)
	return;
    endRange = NSMakeRange([self textLength], 0);
    [self replaceCharactersInRange:endRange withRTF:data];
}

- (void)appendRTFDData:(NSData *)data;
{
    NSRange endRange;

    if (data == nil || [data length] == 0)
	return;
    endRange = NSMakeRange([self textLength], 0);
    [self replaceCharactersInRange:endRange withRTFD:data];
}

- (void)appendRTFString:(NSString *)string;
{
    NSData *rtfData;
    NSRange endRange;

    if ([NSString isEmptyString:string])
	return;
    rtfData = [string dataUsingEncoding:[NSString defaultCStringEncoding] allowLossyConversion:YES];
    endRange = NSMakeRange([self textLength], 0);
    [self replaceCharactersInRange:endRange withRTF:rtfData];
}

- (NSData *)textData;
{
    return [[self string] dataUsingEncoding:[NSString defaultCStringEncoding] allowLossyConversion:YES];
}

- (NSData *)rtfData;
{
    return [self RTFFromRange:NSMakeRange(0, [self textLength])];
}

- (NSData *)rtfdData;
{
    return [self RTFDFromRange:NSMakeRange(0, [self textLength])];
}

- (void)setRTFData:(NSData *)rtfData;
{
    [self replaceCharactersInRange:NSMakeRange(0, [self textLength]) withRTF:rtfData];
}

- (void)setRTFDData:(NSData *)rtfdData;
{
    [self replaceCharactersInRange:NSMakeRange(0, [self textLength]) withRTFD:rtfdData];
}

- (void)setRTFString:(NSString *)string;
{
    NSData *rtfData;
    NSRange fullRange;

    rtfData = [string dataUsingEncoding:[NSString defaultCStringEncoding] allowLossyConversion:YES];
    fullRange = NSMakeRange(0, [self textLength]);
    [self replaceCharactersInRange:fullRange withRTF:rtfData];
}

- (void)setTextFromString:(NSString *)aString;
{
    [self setString:aString != nil ? aString : @""];
}

- (NSString *)substringWithRange:(NSRange)aRange;
{
    NSString *result;
    @try {
        result = [[self string] substringWithRange:aRange];
    } @catch (NSException *exc) {
	result = @"";
    }
    return result;
}

- (NSRange)trackingAndKerningRange;
{
    NSRange selectionRange = [self selectedRange];
    NSUInteger textLength = [[self string] length];
    
    if ((selectionRange.length == 0) && (selectionRange.location > 0)) {
        // If the selection is zero-length (and it's not at the beginning of the text), the tracking/kerning attribute should apply to the character before the insertion point.
        selectionRange = NSMakeRange(selectionRange.location - 1, 1);
        
    } else if ((selectionRange.length > 1) && (NSMaxRange(selectionRange) < textLength)) {
        // If the selection is larger than a single character (and it doesn't run to the end of the text), the tracking/kerning attribute should not apply to the last character of the selection (because if it did, it would affect the spacing between the end of the selection and the following character).
        selectionRange.length -= 1;
    }
    
    return selectionRange;
}

// OAFindControllerAware informal protocol

- (id <OAFindControllerTarget>)omniFindControllerTarget;
{
    return self;
}

// OAFindControllerTarget

- (BOOL)findPattern:(id <OAFindPattern>)pattern backwards:(BOOL)backwards wrap:(BOOL)wrap;
{
    if ([self findPattern:pattern backwards:backwards ignoreSelection:NO])
        return YES;

    if (!wrap)
        return NO;

    // Try again, ignoring the selection and searching from one end or the other.
    return [self findPattern:pattern backwards:backwards ignoreSelection:YES];
}

// OASearchableContent protocol

- (BOOL)findPattern:(id <OAFindPattern>)pattern backwards:(BOOL)backwards ignoreSelection:(BOOL)ignoreSelection;
{
    // TODO: I'd really like to just move all these methods to NSTextView-OAExtensions.m and not pretend that someone else subclasses NSText.
    NSTextStorage *textStorage = [(NSTextView *)self textStorage];
    unsigned int length = [textStorage length];
    if (!length)
        return NO;
    
    NSRange searchedRange, foundRange;
    BOOL found;

    if (ignoreSelection)
        found = [textStorage findPattern:pattern inRange:NSMakeRange(0, length) foundRange:&foundRange];
    else {
        NSRange selectedRange = [self selectedRange];
        if (backwards)
            searchedRange = NSMakeRange(0, selectedRange.location);
        else
            searchedRange = NSMakeRange(NSMaxRange(selectedRange), length - NSMaxRange(selectedRange));
        found = [textStorage findPattern:pattern inRange:searchedRange foundRange:&foundRange];
    }
            
    if (found) {
        [self setSelectedRange:foundRange];
        [self scrollRangeToVisible:foundRange];
        [[self window] makeFirstResponder:self];
    }
    return found;
}

@end

@implementation NSTextView (OAExtensions)

- (unsigned int)textLength;
{
    return [[self textStorage] length];
}

- (void)replaceSelectionWithString:(NSString *)aString;
{
    NSTextStorage *textStorage;
    NSRange selectedRange;
    
    selectedRange = [self selectedRange];
    textStorage = [self textStorage];
    // this is almost guaranteed to succeed by the time we get here, but going through -shouldChangeTextInRange:withString: is what hooks us into the undo manager.
    if ([self isEditable] && [self shouldChangeTextInRange:selectedRange replacementString:aString]) {
        [textStorage replaceCharactersInRange:selectedRange withString:aString];
        [self didChangeText];
        selectedRange.length = [aString length];
        [self setSelectedRange:selectedRange];
    } else {
        NSBeep();
    }
}

- (void)replaceAllOfPattern:(id <OAFindPattern>)pattern inRange:(NSRange)searchRange;
{
    NSTextStorage *textStorage;
    NSString *string, *replacement;
    NSRange remainingRange;
    
    textStorage = [self textStorage];
    string = [textStorage string];
    remainingRange = searchRange;
    while (remainingRange.length != 0) {
        NSRange foundRange;

        if (![pattern findInRange:remainingRange ofString:string foundRange:&foundRange])
            break;

        replacement = [pattern replacementStringForLastFind];

        // this is almost guaranteed to succeed by the time we get here, but going through -shouldChangeTextInRange:withString: is what hooks us into the undo manager.
        if ([self isEditable] && [self shouldChangeTextInRange:foundRange replacementString:replacement]) {
            [textStorage replaceCharactersInRange:foundRange withString:replacement];
            [self didChangeText];
        } else {
            NSBeep();
            break;
        }

        OBINVARIANT(string == [self string]); // Or we should cache it again

        // Update our remaining range

        // The length of the new remaining range is the distance from the end of the old found range to the end of the old remaining range (i.e., the end of the old remaining range minus the end of the old found range).
        remainingRange.length = NSMaxRange(remainingRange) - NSMaxRange(foundRange);

        // The location of the new remaining range is the beginning of the old found range plus the length of the replaced string
        remainingRange.location = foundRange.location + [replacement length];
    }
}

- (void)replaceAllOfPattern:(id <OAFindPattern>)pattern;
{
    [self replaceAllOfPattern:pattern inRange:NSMakeRange(0, [[self string] length])];
}

- (void)replaceAllOfPatternInCurrentSelection:(id <OAFindPattern>)pattern;
{
    [self replaceAllOfPattern:pattern inRange:[self selectedRange]];
}

@end
