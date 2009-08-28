// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSTextStorage-OAExtensions.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniFoundation/NSObject-OFAppleScriptExtensions.h>

#import <OmniAppKit/OAFindPattern.h>
#import <OmniAppKit/OARegExFindPattern.h>

RCS_ID("$Id$")


// To avoid warnings from OBReplaceMethodImplementationWithSelector, we can't use int or NSInteger since we have NS_BUILD_32_LIKE_64 on, NSUInteger would become unsigned long, which woule mismatch with int in AppKit's signature.  
#if defined (__LP64__)
    #define CHARACTER_INDEX_TYPE NSInteger
#else
    #define CHARACTER_INDEX_TYPE unsigned
#endif

// <bug://bugs/26796> -- If you are linked against 10.4, Apple's code will raise if you access 'last character of SomeText' and 'SomeText' is empty.  Under earlier versions, it will create an NSSubTextStorage that contains the out-of-bounds reference, leading to crashes.   They have a log message that comes out under 10.4 saying that you'll get an exception under earlier OS's, but they goofed and you still get the crash.  Testing shows that this is only a problem in the 'characters' version (presumably since they can directly index the characters and thus avoided building an array and the bounds checking code).
// 2005/03/23 -- Arg.  Testing again with all 10.4 SDKs this still fails.  Re-enabling the hack unconditionally for now.
#if 1 || !defined(MAC_OS_X_VERSION_10_4) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_4
@interface NSTextStorage (PrivateAPI)
- (id)valueInCharactersAtIndex:(CHARACTER_INDEX_TYPE)i;
@end

@implementation NSTextStorage (OAScriptFixes)

static id (*originalValueInCharactersAtIndex)(id self, SEL _cmd, CHARACTER_INDEX_TYPE i) = NULL;

+ (void)didLoad;
{
    originalValueInCharactersAtIndex = (void *)OBReplaceMethodImplementationWithSelector(self,  @selector(valueInCharactersAtIndex:), @selector(replacement_valueInCharactersAtIndex:));
}

- (id)replacement_valueInCharactersAtIndex:(CHARACTER_INDEX_TYPE)characterIndex;
{
    CHARACTER_INDEX_TYPE originalIndex = characterIndex;
    NSUInteger length = [self length];
    if (length == 0)
	return nil;
    
    // -1 means 'last'
    if (characterIndex < 0) {
	characterIndex += length;
	if (characterIndex < 0) // past the beginning
	    return nil;
    }
    
    if ((NSUInteger)characterIndex >= length) // past the end
	return nil;
    
    return originalValueInCharactersAtIndex(self, _cmd, originalIndex);
}

@end
#endif

@interface NSTextStorage (NSScripting)
- (void)setFontSize:(float)size;
@end

@interface NSScriptSuiteRegistry (PrivateAPI)
- (void)_setClassDescription:(NSScriptClassDescription *)classDesc forAppleEventCode:(unsigned long)eventCode;
@end

@implementation NSTextStorage (OAExtensions)

+ (void)didLoad;
{
    NSScriptCoercionHandler *handler = [NSScriptCoercionHandler sharedCoercionHandler];
    [handler registerCoercer:self selector:@selector(coerceList:toClass:) toConvertFromClass:[NSArray class] toClass:self];
    [self registerConversionFromRecord];
}

// Basically, I think undo was implemented incorrectly (possibly for good reasons) on NSTextView/NSTextStorage. The model should be responsible for registering undo events, and the view responsible for setting undo action names.  But in this case, NSTextView really does the registration (prossibly for efficiency reasons -- coalescing character changes seems like an obvious possibility).
// This method tries to find an undo manager by finding an attached text view.  This is used by OAStyledTextStorage and when logging undo events generated from OAStyle (i.e., not from the view).  If the undo support on NSTextStorage had been done 'properly' (at least according to me :) in the first place this wouldn't be necessary.
- (NSUndoManager *)undoManager;
{
    NSUndoManager *undoManager = nil;
    NSArray       *layoutManagers;
    unsigned int   layoutManagerIndex;

    layoutManagers = [self layoutManagers];
    layoutManagerIndex = [layoutManagers count];
    while (layoutManagerIndex--) {
        NSLayoutManager *layoutManager = [layoutManagers objectAtIndex:layoutManagerIndex];

        // If a OAStyledTextStorage is used for one of the text storage AppleScript methods (like characters), then a NSSubTextStorage (private class) is created that refers to it and apparently this private class adds itself as a layout manager (to find out about changes to the base text, I'd guess).  Terrible.
        if (![layoutManager respondsToSelector:@selector(textContainers)])
            continue;

        NSArray *textContainers = [layoutManager textContainers];
        unsigned int textContainerIndex = [textContainers count];
        while (textContainerIndex--) {
            NSTextContainer *textContainer = [textContainers objectAtIndex:textContainerIndex];
            NSTextView *textView = [textContainer textView];

            if (textView) {
                if (!undoManager)
                    undoManager = [textView undoManager];
                OBASSERT(undoManager == [textView undoManager]);
            }
        }
    }

    // It is perfectly find for a NSTextStorage to not have an undo manager (just not hooked to a text view).
    return undoManager;
}

//
//  Older non-OAStyle stuff (see NSTextStorage-OAStyleExtensions.[hm])
//

- (BOOL)isUnderlined;
{
    id value;
    
    if (![self length])
        return NO;
    value = [self attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL];
    return value != nil && [value intValue] != NSUnderlineStyleNone;
}

- (void)setIsUnderlined:(BOOL)value;
{
    NSRange range;

    [self beginEditing];
    range = NSMakeRange(0, [self length]);
    if (value)
        [self addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:NSUnderlineStyleSingle] range:range];
    else
        // Storing the default value explicitly causes the scripting -attributeRuns method to report more runs than there really are.  We should try to not store default attribute values, therefor.
        [self removeAttribute:NSUnderlineStyleAttributeName range:range];
    [self endEditing];
}

- (NSNumber *)superscriptLevel;
{
    if ([self length] == 0)
        return nil;
    return [self attribute:NSSuperscriptAttributeName atIndex:0 effectiveRange:NULL];
}

- (void)setSuperscriptLevel:(NSNumber *)value;
{
    [self beginEditing];
    {
        BOOL remove = NO;
        NSRange range;

        if ([value respondsToSelector: @selector(floatValue)]) {
            // TODO: Should we convert the value to a NSNumber here (might be a string formatted float, for example)?
            remove = [(id)value floatValue] == 0.0f;
        } else {
            // OFISNULL doesn't check for +[NSNull null]
            OBASSERT(OFISNULL(value) || (NSNull *)value == [NSNull null]);
            remove = YES;
        }

        range = NSMakeRange(0, [self length]);
        if (remove)
            // Storing the default value explicitly causes the scripting -attributeRuns method to report more runs than there really are.  We should try to not store default attribute values, therefor.
            [self removeAttribute: NSSuperscriptAttributeName range:range];
        else
            [self addAttribute:NSSuperscriptAttributeName value:value range:range];
    }
    [self endEditing];
}

- (NSNumber *)baselineOffset;
{
    if ([self length] == 0)
        return nil;
    return [self attribute:NSBaselineOffsetAttributeName atIndex:0 effectiveRange:NULL];
}

- (void)setBaselineOffset:(NSNumber *)value;
{
    [self beginEditing];
    {
        BOOL remove = NO;
        NSRange range;

        if ([value respondsToSelector: @selector(floatValue)]) {
            // TODO: Should we convert the value to a NSNumber here (might be a string formatted float, for example)?
            remove = [(id)value floatValue] == 0.0f;
        } else {
            // OFISNULL doesn't check for +[NSNull null]
            OBASSERT(OFISNULL(value) || (NSNull *)value == [NSNull null]);
            remove = YES;
        }

        range = NSMakeRange(0, [self length]);
        if (remove)
            // Storing the default value explicitly causes the scripting -attributeRuns method to report more runs than there really are.  We should try to not store default attribute values, therefor.
            [self removeAttribute: NSBaselineOffsetAttributeName range:range];
        else
            [self addAttribute:NSBaselineOffsetAttributeName value:value range:NSMakeRange(0, [self length])];
    }
    [self endEditing];
}

- (int)textAlignment;
{
    NSParagraphStyle *paragraphStyle;
    
    if (![self length])
        return 'OTa0'; // left
    paragraphStyle = [self attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    switch([paragraphStyle alignment]) {
        case NSLeftTextAlignment: return 'OTa0';
        case NSCenterTextAlignment: return 'OTa1';
        case NSRightTextAlignment: return 'OTa2';
        case NSJustifiedTextAlignment: return 'OTa3';
        case NSNaturalTextAlignment:
        default:
            return 'OTa0'; // assume natural is left aligned
    }
}

- (void)setTextAlignment:(int)value;
{
    int newAlignment;
    NSParagraphStyle *paragraphStyle;
    NSMutableParagraphStyle *mutable;
    
    if (![self length])
        return;
    
    switch(value - 'OTa0') {
        case 0: 
            newAlignment = NSLeftTextAlignment;
            break;
        case 1:
            newAlignment = NSCenterTextAlignment;
            break;
        case 2:
            newAlignment = NSRightTextAlignment;
            break;
        case 3:
            newAlignment = NSJustifiedTextAlignment;
            break;
        default:
            newAlignment = NSLeftTextAlignment;
            break;
    }
    paragraphStyle = [self attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    if (!paragraphStyle) 
        paragraphStyle = [NSParagraphStyle defaultParagraphStyle];
    mutable = [paragraphStyle mutableCopy];
    [mutable setAlignment:newAlignment];

    if ([mutable isEqual: [NSParagraphStyle defaultParagraphStyle]]) {
        [mutable release];
        mutable = nil;
    }
        
    [self beginEditing];
    NSRange range = NSMakeRange(0, [self length]);
    if (mutable)
        [self addAttribute:NSParagraphStyleAttributeName value:mutable range:range];
    else
        // Storing the default value explicitly causes the scripting -attributeRuns method to report more runs than there really are.  We should try to not store default attribute values, therefor.
        [self removeAttribute:NSParagraphStyleAttributeName range:range];
    [self endEditing];

    [mutable release];
}

- (NSString *)text;
{
    return [self string];
}

- (void)setText:(NSString *)someText;
{
    [self beginEditing];
    [self replaceCharactersInRange:NSMakeRange(0, [self length]) withString:someText];
    [self endEditing];
}

- (void)convertFontsToHaveTrait:(NSFontTraitMask)trait;
{
    unsigned int position  = 0;
    unsigned int length    = [self length];
    NSFontManager *manager = [NSFontManager sharedFontManager];
    
    [self beginEditing];
    while (position < length) {
        NSRange range;
        NSFont *font = [self attribute:NSFontAttributeName atIndex:position effectiveRange:&range];
        font = [manager convertFont:font toHaveTrait:trait];
        // TODO: We could remove the font name attribute if it is being set to Helvetica 12pt (the default value for NSFontAttributeName).
        [self addAttribute:NSFontAttributeName value:font range:range];
        position = NSMaxRange(range);
    }
    [self endEditing];
}

- (void)handleBoldScriptCommand:(NSScriptCommand *)command;
{
    [self convertFontsToHaveTrait:NSBoldFontMask];
}

- (void)handleItalicizeScriptCommand:(NSScriptCommand *)command;
{
    [self convertFontsToHaveTrait:NSItalicFontMask];
}

- (void)handleUnboldScriptCommand:(NSScriptCommand *)command;
{
    [self convertFontsToHaveTrait:NSUnboldFontMask];
}

- (void)handleUnitalicizeScriptCommand:(NSScriptCommand *)command;
{
    [self convertFontsToHaveTrait:NSUnitalicFontMask];
}

- (void)handleUnderlineScriptCommand:(NSScriptCommand *)command;
{
    [self setIsUnderlined:YES];
}

- (void)handleUnunderlineScriptCommand:(NSScriptCommand *)command;
{
    [self setIsUnderlined:NO];
}

+ (NSObject <OAFindPattern>*)findPatternForReplaceCommand:(NSScriptCommand *)command;
{
    NSString *string, *replacement;
    NSDictionary *args;
    NSObject <OAFindPattern>*pattern;
    
    args = [command evaluatedArguments];
    replacement = [args objectForKey:@"replacement"];
    if (!replacement) {
	[NSException raise:NSInvalidArgumentException format:@"No replacement specified."];
        return nil;
    }
    
    BOOL ignoreCase = [[args objectForKey:@"ignoreCase"] boolValue];
    BOOL wholeWords = [[args objectForKey:@"wholeWords"] boolValue];
    
    if ((string = [args objectForKey:@"string"])) {
        pattern = [[OAFindPattern alloc] initWithString:string ignoreCase:ignoreCase wholeWord:wholeWords backwards:NO];
    } else if ((string = [args objectForKey:@"regexp"])) {
        pattern = [[OARegExFindPattern alloc] initWithString:string selectedSubexpression:SELECT_FULL_EXPRESSION backwards:NO];
    } else {
	[NSException raise:NSInvalidArgumentException format:@"No 'string' or 'regexp' specified."];
        return nil;
    }
    
    [pattern setReplacementString:replacement];
    return [pattern autorelease];
}

- (void)replaceUsingPattern:(NSObject <OAFindPattern>*)pattern;
{
    NSRange searchRange;
    NSRange range;
    NSString *string, *replacement;
    
    if (pattern == nil)
        return;
        
    [self beginEditing];
    string = [self string];
    searchRange = NSMakeRange(0, [string length]);
    while (searchRange.length != 0) {
        if (![pattern findInRange:searchRange ofString:string foundRange:&range])
            break;

        replacement = [pattern replacementStringForLastFind];
        [self replaceCharactersInRange:range withString:replacement];
        searchRange.location = range.location + [replacement length];
        searchRange.length = [string length] - searchRange.location;
    }
    [self endEditing];
}

// This is split out from our NSText(OAExtension) find support so that it can be subclassed easily.
- (BOOL)findPattern:(id <OAFindPattern>)pattern inRange:(NSRange)searchRange foundRange:(NSRange *)foundRange;
{
    return [pattern findInRange:searchRange ofString:[self string] foundRange:foundRange];
}

- (void)handleReplaceScriptCommand:(NSScriptCommand *)command;
{
    [self replaceUsingPattern:[isa findPatternForReplaceCommand:command]];
}

+ (id)coerceRecord:(NSDictionary *)dictionary toClass:(Class)aClass
{
    NSTextStorage *result = [[[NSTextStorage alloc] init] autorelease];

    // Set text first so we have a range to apply the other attributes over.
    NSMutableDictionary *tempDict = [dictionary mutableCopy];
    NSNumber *textFourCharCode = [NSNumber numberWithInt:'ctxt'];
    [result setText:[tempDict objectForKey:textFourCharCode]]; 
    [tempDict removeObjectForKey:textFourCharCode];

    //  Squirrel way the size and set it last so that, say, setting the font name doesn't say "Verdana?  That's 12pt!" and blow away the size.  The only font descriptor attributes that we support are font name and size.  If someone were to add, say, font weight or italic, this would become order dependent and we wouldn't be taking advantage of NSFontDescriptor's ability to find the best match.  Switch to NSFontDescriptor, then.
    NSNumber *fontSizeFourCharCode = [NSNumber numberWithInt:'ptsz'];
    NSNumber *fontSize = [tempDict objectForKey:fontSizeFourCharCode];
    [tempDict removeObjectForKey:fontSizeFourCharCode];
    
    [result appleScriptTakeAttributesFromRecord:tempDict];
    [tempDict release];
    
    if (fontSize != nil)
        [result setFontSize:[fontSize floatValue]];
    /* NSTextStorage -setFontSize: takes an actual float, not a CGFloat */
    
    return result;
}

+ (id)coerceList:(NSArray *)array toClass:(Class)aClass;
{
    NSTextStorage *result = [[[NSTextStorage alloc] init] autorelease];
    NSScriptCoercionHandler *coercer = [NSScriptCoercionHandler sharedCoercionHandler];
    int index, count;
    
    count = [array count];
    
    [result beginEditing];
    for (index = 0; index < count; index++)
        [result appendAttributedString:[coercer coerceValue:[array objectAtIndex:index] toClass:self]];
    [result endEditing];
    
    return result;
}

- (id)appleScriptBlankInit;
{
    [self init];
    [self setText:@" "]; // so there will be something to apply traits to
    return self;
}

- (NSArray *)appleScriptExtraAttributeKeys;
{
    return [NSArray arrayWithObject:@"text"];
}

- (NSString *)appleScriptMakeProperties;
{
    NSArray *parts;

    parts = [self attributeRuns];
    if ([parts count] == 1)
        return [super appleScriptMakeProperties];
    else {
        NSMutableString *result = [NSMutableString stringWithString:@"{"];
        BOOL useComma = NO;
        int index, count;
        
        count = [parts count];
        for (index = 0; index < count; index++) {
            if (useComma)
                [result appendString:@", "];
            else
                useComma = YES;
            [result appendString:[[parts objectAtIndex:index] appleScriptMakeProperties]];
        }
        [result appendString:@"}"];
        return result;
    }
}

- (id)attachmentAtCharacterIndex:(unsigned int)characterIndex;
{
    return [self attribute:NSAttachmentAttributeName atIndex:characterIndex effectiveRange:NULL];
}

@end
