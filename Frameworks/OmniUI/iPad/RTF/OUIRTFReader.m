// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIRTFReader.h>

#import <Foundation/NSAttributedString.h>
#import <OmniBase/assertions.h>
#import <OmniFoundation/NSString-OFUnicodeCharacters.h>
#import <OmniFoundation/NSMutableAttributedString-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <OmniFoundation/OFStringScanner.h>
#import <OmniAppKit/OAFontDescriptor.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <CoreText/CTParagraphStyle.h>
#import <CoreText/CTStringAttributes.h>
#endif

RCS_ID("$Id$");

#ifdef DEBUG_kc0
#define DEBUG_RTF_READER
#endif

@class OUIRTFReaderAction;

@interface OUIRTFReader ()

@property (readwrite, retain) NSAttributedString *attributedString;

+ (void)_registerKeyword:(NSString *)keyword action:(OUIRTFReaderAction *)action;

- (id)_initWithRTFString:(NSString *)rtfString;
- (void)_parseRTFGroupWithSemicolonAction:(OUIRTFReaderAction *)semicolonAction;
- (void)_parseRTF;
- (void)_parseKeyword;
- (void)_parseControlSymbol;
- (void)_pushRTFState;
- (void)_popRTFState;
- (void)_actionSkipDestination;

- (CGColorRef)_newCurrentColorTableCGColor;
- (void)_resetCurrentColorTableColor;
- (void)_addColorTableEntry;
- (void)_actionReadColorTable;
- (CGColorRef)_colorAtIndex:(int)colorTableIndex;

- (void)_addFontTableEntry;
- (void)_actionReadFontTable;
- (void)_actionReadFontCharacterSet:(int)characterSet;
- (NSString *)_fontNameAtIndex:(int)fontTableIndex;

- (void)_actionUnderline:(int)value;
- (void)_actionUnderlineStyle:(int)value;

- (void)_actionAppendString:(NSString *)string;
- (void)_actionSetUnicodeSkipCount:(int)newCount;
- (void)_actionInsertUnicodeCharacter:(int)unicodeCharacter;
- (void)_actionInsertPageBreak;
- (void)_actionNewParagraph;
- (void)_actionParagraphDefault;
- (void)_actionParagraphAlignCenter;
- (void)_actionParagraphAlignJustify;
- (void)_actionParagraphAlignLeft;
- (void)_actionParagraphAlignRight;
- (void)_actionParagraphFirstLineIndent:(int)newValue;
- (void)_actionParagraphLeftIndent:(int)newValue;
- (void)_actionParagraphRightIndent:(int)newValue;

@end

#define NO_RIGHT_INDENT (-999999)

@interface OUIRTFReaderState : OFObject <NSCopying>
{
    @public

    NSMutableString *_alternateDestination;
    CFStringEncoding _stringEncoding;
    id _foregroundColor;
    CGFloat _fontSize;
    int _fontNumber;
    int _fontCharacterSet;
    unsigned int _underline;

    int _unicodeSkipCount;
    struct {
        unsigned int discardText:1;
        unsigned int bold:1;
        unsigned int italic:1;
    } _flags;

    struct {
        CTTextAlignment alignment;
        int firstLineIndent;
        int leftIndent;
        int rightIndent;
    } _paragraph;

    NSMutableDictionary *_cachedStringAttributes;
}

@property (nonatomic, readwrite, retain) NSMutableString *alternateDestination;
@property (readwrite, retain) id foregroundColor;
@property (readwrite) CGFloat fontSize;
@property (readwrite) int fontNumber;
@property (readwrite) BOOL bold;
@property (readwrite) BOOL italic;
@property (readwrite) unsigned int underlineStyle;
@property (readwrite) int fontCharacterSet;
@property (readwrite) CTTextAlignment paragraphAlignment;
@property (readwrite) int paragraphFirstLineIndent;
@property (readwrite) int paragraphLeftIndent;
@property (readwrite) int paragraphRightIndent;

- (NSMutableDictionary *)stringAttributesForReader:(OUIRTFReader *)reader;
- (CFStringEncoding)fontEncoding;
- (void)resetParagraphAttributes;

@end

@interface OUIRTFReaderAction : OFObject
- (void)performActionWithParser:(OUIRTFReader *)parser;
- (void)performActionWithParser:(OUIRTFReader *)parser parameter:(int)parameter;
@end

@interface OUIRTFReaderSelectorAction : OUIRTFReaderAction
{
@private
    SEL _selector;
    IMP _implementation;
    int _defaultValue;
    BOOL _forceValue;
}

- (id)initWithSelector:(SEL)selector defaultValue:(int)defaultValue;
- (id)initWithSelector:(SEL)selector value:(int)defaultValue;
- (id)initWithSelector:(SEL)selector;

@end

@interface OUIRTFReaderAppendStringAction : OUIRTFReaderAction
{
@private
    NSString *_string;
}

+ (OUIRTFReaderAction *)appendStringActionWithString:(NSString *)string;
- (id)initWithString:(NSString *)string;

@end

@interface OUIRTFReaderFontTableEntry : OFObject
{
@private
    NSString *_name;
    CFStringEncoding _encoding;
}

@property (readwrite, retain) NSString *name;
@property (readwrite) CFStringEncoding encoding;

@end

@implementation OUIRTFReader

@synthesize attributedString = _attributedString;

static OFCharacterSet *StandardReservedSet, *SemicolonReservedSet;
static OFCharacterSet *LetterSequenceDelimiters;
static OFCharacterSet *NumericParameterDelimiters;
static NSMutableDictionary *KeywordActions;

+ (void)initialize;
{
    OBINITIALIZE;

    StandardReservedSet = [[OFCharacterSet alloc] initWithString:@"\\{}\r\n"];
    SemicolonReservedSet = [[OFCharacterSet alloc] initWithString:@"\\{}\r\n;"];

    LetterSequenceDelimiters = [[OFCharacterSet alloc] init];
    [LetterSequenceDelimiters addAllCharacters];
    [LetterSequenceDelimiters removeCharactersInString:@"abcdefghijklmnopqrstuvwxyz"];
    [LetterSequenceDelimiters removeCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ"]; // Word 97-2000 keywords do not follow the requirement that keywords may not contain any uppercase 
    NumericParameterDelimiters = [[OFCharacterSet alloc] init];
    [NumericParameterDelimiters addAllCharacters];
    [NumericParameterDelimiters removeCharactersInString:@"0123456789"];

    KeywordActions = [[NSMutableDictionary alloc] init];

    OUIRTFReaderAction *skipDestinationAction = [[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionSkipDestination)] autorelease];

    // Unicode characters
    [self _registerKeyword:@"uc" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionSetUnicodeSkipCount:)] autorelease]];
    [self _registerKeyword:@"u" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionInsertUnicodeCharacter:)] autorelease]];

    // Special keywords
    [self _registerKeyword:@"page" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionInsertPageBreak)] autorelease]];

    // Character traits
    [self _registerKeyword:@"cb" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionBackgroundColor:)] autorelease]];
    [self _registerKeyword:@"cf" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionForegroundColor:)] autorelease]];
    [self _registerKeyword:@"b" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionBold:)] autorelease]];
    [self _registerKeyword:@"i" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionItalic:)] autorelease]];
    [self _registerKeyword:@"fs" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionFontSize:)] autorelease]];
    [self _registerKeyword:@"f" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionFontNumber:)] autorelease]];
    
    // Underlines
    [self _registerKeyword:@"ul" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderline:)] autorelease]];
    [self _registerKeyword:@"uld" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderlineStyle:) value:(kCTUnderlineStyleSingle|kCTUnderlinePatternDot)] autorelease]];
    OUIRTFReaderAction *uldash = [[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderlineStyle:) value:(kCTUnderlineStyleSingle|kCTUnderlinePatternDash)] autorelease];
    [self _registerKeyword:@"uldash" action:uldash];
    [self _registerKeyword:@"uldashd" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderlineStyle:) value:(kCTUnderlineStyleSingle|kCTUnderlinePatternDashDot)] autorelease]];
    [self _registerKeyword:@"uldashdd" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderlineStyle:) value:(kCTUnderlineStyleSingle|kCTUnderlinePatternDashDotDot)] autorelease]];
    OUIRTFReaderAction *uldb = [[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderlineStyle:) value:kCTUnderlineStyleDouble] autorelease];
    [self _registerKeyword:@"uldb" action:uldb];
    [self _registerKeyword:@"ulnone" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderlineStyle:) value:kCTUnderlineStyleNone] autorelease]];
    OUIRTFReaderAction *ulth = [[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderlineStyle:) value:kCTUnderlineStyleThick] autorelease];
    [self _registerKeyword:@"ulth" action:ulth];
    [self _registerKeyword:@"ulthd" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderlineStyle:) value:(kCTUnderlineStyleThick|kCTUnderlinePatternDot)] autorelease]];
    OUIRTFReaderAction *ulthdash = [[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderlineStyle:) value:(kCTUnderlineStyleThick|kCTUnderlinePatternDash)] autorelease];
    [self _registerKeyword:@"ulthdash" action:ulthdash];
    [self _registerKeyword:@"ulthdashd" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderlineStyle:) value:(kCTUnderlineStyleThick|kCTUnderlinePatternDashDot)] autorelease]];
    [self _registerKeyword:@"ulthdashdd" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderlineStyle:) value:(kCTUnderlineStyleThick|kCTUnderlinePatternDashDotDot)] autorelease]];
    // Underline styles we don't actually support; translate them into something similar
    [self _registerKeyword:@"ulwave" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionUnderlineStyle:) value:kCTUnderlineStyleSingle] autorelease]];
    [self _registerKeyword:@"ulhwave" action:ulth];
    [self _registerKeyword:@"ulldash" action:uldash];
    [self _registerKeyword:@"ulthldash" action:ulthdash];
    [self _registerKeyword:@"ululdbwave" action:uldb];

    // Paragraph formatting properties
    [self _registerKeyword:@"par" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionNewParagraph)] autorelease]];
    [self _registerKeyword:@"pard" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionParagraphDefault)] autorelease]];
    [self _registerKeyword:@"qc" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionParagraphAlignCenter)] autorelease]];
    [self _registerKeyword:@"qj" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionParagraphAlignJustify)] autorelease]];
    [self _registerKeyword:@"ql" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionParagraphAlignLeft)] autorelease]];
    [self _registerKeyword:@"qr" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionParagraphAlignRight)] autorelease]];
    [self _registerKeyword:@"fi" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionParagraphFirstLineIndent:)] autorelease]];
    [self _registerKeyword:@"li" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionParagraphLeftIndent:)] autorelease]];
    [self _registerKeyword:@"ri" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionParagraphRightIndent:)] autorelease]];

    // Color table destination
    [self _registerKeyword:@"colortbl" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionReadColorTable)] autorelease]];
    [self _registerKeyword:@"red" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionReadColorTableRedValue:)] autorelease]];
    [self _registerKeyword:@"green" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionReadColorTableGreenValue:)] autorelease]];
    [self _registerKeyword:@"blue" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionReadColorTableBlueValue:)] autorelease]];

    // Font table destination
    [self _registerKeyword:@"fonttbl" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionReadFontTable)] autorelease]];
    [self _registerKeyword:@"fcharset" action:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_actionReadFontCharacterSet:)] autorelease]];

    // Unsupported destinations
    [self _registerKeyword:@"author" action:skipDestinationAction];
    [self _registerKeyword:@"buptim" action:skipDestinationAction];
    [self _registerKeyword:@"comment" action:skipDestinationAction];
    [self _registerKeyword:@"creatim" action:skipDestinationAction];
    [self _registerKeyword:@"doccomm" action:skipDestinationAction];
    [self _registerKeyword:@"footer" action:skipDestinationAction];
    [self _registerKeyword:@"footerf" action:skipDestinationAction];
    [self _registerKeyword:@"footerl" action:skipDestinationAction];
    [self _registerKeyword:@"footerr" action:skipDestinationAction];
    [self _registerKeyword:@"footnote" action:skipDestinationAction];
    [self _registerKeyword:@"ftncn" action:skipDestinationAction];
    [self _registerKeyword:@"ftnsep" action:skipDestinationAction];
    [self _registerKeyword:@"ftnsepc" action:skipDestinationAction];
    [self _registerKeyword:@"header" action:skipDestinationAction];
    [self _registerKeyword:@"headerf" action:skipDestinationAction];
    [self _registerKeyword:@"headerl" action:skipDestinationAction];
    [self _registerKeyword:@"headerr" action:skipDestinationAction];
    [self _registerKeyword:@"info" action:skipDestinationAction];
    [self _registerKeyword:@"keywords" action:skipDestinationAction];
    [self _registerKeyword:@"operator" action:skipDestinationAction];
    [self _registerKeyword:@"pict" action:skipDestinationAction];
    [self _registerKeyword:@"printim" action:skipDestinationAction];
    [self _registerKeyword:@"private1" action:skipDestinationAction];
    [self _registerKeyword:@"revtim" action:skipDestinationAction];
    [self _registerKeyword:@"rxe" action:skipDestinationAction];
    [self _registerKeyword:@"stylesheet" action:skipDestinationAction];
    [self _registerKeyword:@"subject" action:skipDestinationAction];
    [self _registerKeyword:@"tc" action:skipDestinationAction];
    [self _registerKeyword:@"title" action:skipDestinationAction];
    [self _registerKeyword:@"txe" action:skipDestinationAction];
    [self _registerKeyword:@"xe" action:skipDestinationAction];
}

#ifdef DEBUG_RTF_READER

+ (NSString *)debugStringForColor:(void *)color;
{
    if (color == NULL)
        return @"(null)";

    const CGFloat *rgbComponents = CGColorGetComponents(color);
    OBASSERT(CGColorGetNumberOfComponents(color) == 4); // Otherwise the format statement below is wrong
    return [NSString stringWithFormat:@"%@ (components=%u, r=%3.2f g=%3.2f b=%3.2f a=%3.2f)", color,
        CGColorGetNumberOfComponents(color),
        rgbComponents[0],
        rgbComponents[1],
        rgbComponents[2],
        rgbComponents[3]];
}

+ (NSString *)debugStringForFont:(OAFontDescriptorPlatformFont)font;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    return [NSString stringWithFormat:@"%@ (%@ %@ %1.1f)",
        font,
        [(NSString *)CTFontCopyLocalizedName(font, kCTFontFullNameKey, NULL) autorelease],
        [(NSString *)CTFontCopyLocalizedName(font, kCTFontStyleNameKey, NULL) autorelease],
        CTFontGetSize(font)];
#else
    return [NSString stringWithFormat:@"%@ (%@ %1.1f)",
        font,
        [font displayName],
        [font pointSize]];
#endif
}

#endif

+ (NSAttributedString *)parseRTFString:(NSString *)rtfString;
{
    NSAttributedString *result = nil;
    OMNI_POOL_START {
        OUIRTFReader *parser = [[self alloc] _initWithRTFString:rtfString];
        result = [parser.attributedString retain];
        [parser release];
#ifdef DEBUG_RTF_READER
        NSLog(@"+[OUIRTFReader parseRTFString]: '%@' -> [%@]", rtfString, result);
#endif
    } OMNI_POOL_END;
    return [result autorelease];
}

+ (void)_registerKeyword:(NSString *)keyword action:(OUIRTFReaderAction *)action;
{
    OBPRECONDITION(KeywordActions != nil);
    [KeywordActions setObject:action forKey:keyword];
}

- (id)_initWithRTFString:(NSString *)rtfString;
{
    [super init];

    _attributedString = [[NSMutableAttributedString alloc] init];
    _scanner = [[OFStringScanner alloc] initWithString:rtfString];
    _currentState = [[OUIRTFReaderState alloc] init];
    _pushedStates = [[NSMutableArray alloc] init];
    _colorTable = [[NSMutableArray alloc] init];
    _fontTable = [[NSMutableArray alloc] init];

    [self _parseRTF];

    return self;
}

- (void)dealloc;
{
    [_attributedString release];
    [_scanner release];
    [_currentState release];
    [_pushedStates release];
    [_colorTable release];
    [_fontTable release];

    [super dealloc];
}

- (void)_handleKeyword:(NSString *)keyword;
{
#ifdef DEBUG_RTF_READER
    NSLog(@"RTF control word: %@", keyword);
#endif
    OUIRTFReaderAction *action = [KeywordActions objectForKey:keyword];
    [action performActionWithParser:self];
}

- (void)_handleKeyword:(NSString *)keyword parameter:(int)parameter;
{
#ifdef DEBUG_RTF_READER
    NSLog(@"RTF control word: %@ parameter:%d", keyword, parameter);
#endif

    OUIRTFReaderAction *action = [KeywordActions objectForKey:keyword];
    [action performActionWithParser:self parameter:parameter];
}

- (void)_actionSkipDestination;
{
#ifdef DEBUG_RTF_READER
    NSLog(@"Skipping destination");
#endif
    _currentState->_flags.discardText = YES;
}

#pragma mark -
#pragma mark Parse color table

- (CGColorRef)_newCurrentColorTableCGColor;
{
    static CGColorSpaceRef rgbColorSpace = NULL;
    if (rgbColorSpace == NULL)
        rgbColorSpace = CGColorSpaceCreateDeviceRGB();

    if (_colorTableRedComponent < 0 || _colorTableGreenComponent < 0 || _colorTableBlueComponent < 0)
        return NULL;

    CGFloat components[] = {_colorTableRedComponent / 255.0f, _colorTableGreenComponent / 255.0f, _colorTableBlueComponent / 255.0f, 1.0f};
    return CGColorCreate(rgbColorSpace, components);
}

- (void)_resetCurrentColorTableColor;
{
    _colorTableRedComponent = -1;
    _colorTableGreenComponent = -1;
    _colorTableBlueComponent = -1;
}

- (void)_addColorTableEntry;
{
    scannerSkipPeekedCharacter(_scanner); // Skip ';'
    CGColorRef currentColor = [self _newCurrentColorTableCGColor];
    if (currentColor != nil) {
        [_colorTable addObject:(id)currentColor];
        CGColorRelease(currentColor);
    } else {
        [_colorTable addObject:[NSNull null]];
    }
    [self _resetCurrentColorTableColor];
}

- (void)_actionReadColorTable;
{
    [self _actionSkipDestination]; // Don't let any text from the color table slip into the output stream
    [self _parseRTFGroupWithSemicolonAction:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_addColorTableEntry)] autorelease]];
}

- (CGColorRef)_colorAtIndex:(int)colorTableIndex;
{
    id colorTableEntry = [_colorTable objectAtIndex:colorTableIndex];
    if ([colorTableEntry isNull])
        return NULL;
    else
        return (CGColorRef)colorTableEntry;
}

#pragma mark -
#pragma mark Parse font table

- (void)_addFontTableEntry;
{
    scannerSkipPeekedCharacter(_scanner); // Skip ';'

    // Read and reset alternate destination
    NSString *fontName = [NSString stringWithString:_currentState.alternateDestination];
    _currentState.alternateDestination = [NSMutableString string];

#ifdef DEBUG_RTF_READER
    NSLog(@"Font table entry: %@", fontName);
#endif

    int fontNumber = _currentState.fontNumber;
    if (fontNumber < 0)
        return; // Protect against bad RTF

    OUIRTFReaderFontTableEntry *fontEntry = [[OUIRTFReaderFontTableEntry alloc] init];
    fontEntry.name = fontName;
    fontEntry.encoding = _currentState.fontEncoding;

    int entryCount = (int)[_fontTable count];
    if (fontNumber < entryCount) {
        [_fontTable replaceObjectAtIndex:fontNumber withObject:fontEntry];
    } else {
        while (fontNumber > entryCount) {
            [_fontTable addObject:[NSNull null]];
            entryCount++;
        }
        [_fontTable addObject:fontEntry];
    }
    [fontEntry release];
}

- (void)_actionReadFontTable;
{
    _currentState.alternateDestination = [NSMutableString string];
    [self _parseRTFGroupWithSemicolonAction:[[[OUIRTFReaderSelectorAction alloc] initWithSelector:@selector(_addFontTableEntry)] autorelease]];
}

- (void)_actionReadFontCharacterSet:(int)characterSet;
{
    _currentState.fontCharacterSet = characterSet;
}

- (NSString *)_fontNameAtIndex:(int)fontTableIndex;
{
    static NSString *DefaultFontName = @"Helvetica";

    if (fontTableIndex >= (int)[_fontTable count])
        return DefaultFontName;
    OUIRTFReaderFontTableEntry *fontTableEntry = [_fontTable objectAtIndex:fontTableIndex];
    if ([fontTableEntry isNull])
        return DefaultFontName;
    return fontTableEntry.name;
}

- (CFStringEncoding)_fontEncodingAtIndex:(int)fontTableIndex;
{
    CFStringEncoding DefaultFontEncoding = kCFStringEncodingWindowsLatin1;
    if (fontTableIndex >= (int)[_fontTable count])
        return DefaultFontEncoding;
    OUIRTFReaderFontTableEntry *fontTableEntry = [_fontTable objectAtIndex:fontTableIndex];
    if ([fontTableEntry isNull])
        return DefaultFontEncoding;
    return fontTableEntry.encoding;
}

#pragma mark -
#pragma mark Actions

- (void)_actionBackgroundColor:(int)colorTableIndex;
{
#ifdef DEBUG_RTF_READER
    CGColorRef color = [self _colorAtIndex:colorTableIndex];
    NSLog(@"Ignoring background color: %@ (%@)", (id)color, [(id)color class]);
#endif
}

- (void)_actionForegroundColor:(int)colorTableIndex;
{
    CGColorRef color = [self _colorAtIndex:colorTableIndex];
#ifdef DEBUG_RTF_READER
    NSLog(@"Setting foreground color: %@", [OUIRTFReader debugStringForColor:color]);
#endif
    _currentState.foregroundColor = (id)color;
}

- (void)_actionBold:(int)value;
{
    _currentState.bold = value != 0;
}

- (void)_actionItalic:(int)value;
{
    _currentState.italic = value != 0;
}

- (void)_actionUnderline:(int)parameter;
{
    [self _actionUnderlineStyle: ( parameter? kCTUnderlineStyleSingle : kCTUnderlineStyleNone )];
}

- (void)_actionUnderlineStyle:(int)value;
{
    _currentState.underlineStyle = value;
}

- (void)_actionFontSize:(int)value;
{
    _currentState.fontSize = value * 0.5f;
}

- (void)_actionFontNumber:(int)value;
{
    _currentState.fontNumber = value;
    _currentState->_stringEncoding = [self _fontEncodingAtIndex:value];
#ifdef DEBUG_RTF_READER
    NSLog(@"Changed font number to %d (string encoding %d=[%@])", value, _currentState->_stringEncoding, CFStringGetNameOfEncoding(_currentState->_stringEncoding));
#endif
}

- (void)_actionReadColorTableRedValue:(int)componentValue;
{
    _colorTableRedComponent = componentValue;
}

- (void)_actionReadColorTableGreenValue:(int)componentValue;
{
    _colorTableGreenComponent = componentValue;
}

- (void)_actionReadColorTableBlueValue:(int)componentValue;
{
    _colorTableBlueComponent = componentValue;
}

- (void)_actionAppendString:(NSString *)string;
{
    OBPRECONDITION(string != nil);

    if (_currentState->_flags.discardText)
        return;

    NSMutableString *alternateDestination = _currentState->_alternateDestination;
    if (alternateDestination != nil)
        [alternateDestination appendString:string];
    else
        [_attributedString appendString:string attributes:[_currentState stringAttributesForReader:self]];
}

- (void)_actionSetUnicodeSkipCount:(int)newCount;
{
    _currentState->_unicodeSkipCount = newCount;
}

- (void)_actionInsertUnicodeCharacter:(int)unicodeCharacter;
{
#ifdef DEBUG_RTF_READER
    NSLog(@"Inserting unicode character %d [%@]", unicodeCharacter, [NSString stringWithCharacter:unicodeCharacter]);
#endif
    [self _actionAppendString:[NSString stringWithCharacter:unicodeCharacter]];
    int skipCount = _currentState->_unicodeSkipCount;
#ifdef DEBUG_RTF_READER
    NSLog(@"Skipping %d characters", skipCount);
#endif
    while (skipCount-- > 0) {
#ifdef DEBUG_RTF_READER
        NSLog(@"... %d [%@]", scannerPeekCharacter(_scanner), [NSString stringWithCharacter:scannerPeekCharacter(_scanner)]);
#endif
        scannerSkipPeekedCharacter(_scanner);
    }
}

- (void)_actionInsertPageBreak;
{
    [self _actionAppendString:@"\f"];
}

- (void)_actionNewParagraph;
{
    [self _actionAppendString:@"\n"];
}

- (void)_actionParagraphDefault;
{
    [_currentState resetParagraphAttributes];
}

- (void)_actionParagraphAlignCenter;
{
    _currentState.paragraphAlignment = kCTCenterTextAlignment;
}

- (void)_actionParagraphAlignJustify;
{
    _currentState.paragraphAlignment = kCTJustifiedTextAlignment;
}

- (void)_actionParagraphAlignLeft;
{
    _currentState.paragraphAlignment = kCTLeftTextAlignment;
}

- (void)_actionParagraphAlignRight;
{
    _currentState.paragraphAlignment = kCTRightTextAlignment;
}

- (void)_actionParagraphFirstLineIndent:(int)newValue;
{
    _currentState.paragraphFirstLineIndent = newValue;
}

- (void)_actionParagraphLeftIndent:(int)newValue;
{
    _currentState.paragraphLeftIndent = newValue;
}

- (void)_actionParagraphRightIndent:(int)newValue;
{
    _currentState.paragraphRightIndent = newValue;
}

#pragma mark -
#pragma mark Parsing engine

- (void)_parseKeyword;
{
    NSString *letterSequence = [_scanner readFullTokenWithDelimiterOFCharacterSet:LetterSequenceDelimiters forceLowercase:NO];
    BOOL parameterIsNegative = NO;
    switch (scannerPeekCharacter(_scanner)) {
        case ' ':
            scannerSkipPeekedCharacter(_scanner);
            [self _handleKeyword:letterSequence];
            break;
        case '-':
            parameterIsNegative = YES;
            scannerSkipPeekedCharacter(_scanner);
            // FALL THROUGH
        case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
        {
            NSString *numericParameterString = [_scanner readFullTokenWithDelimiterOFCharacterSet:NumericParameterDelimiters];
            if (scannerPeekCharacter(_scanner) == ' ')
                scannerSkipPeekedCharacter(_scanner);
            int numericParameter = [numericParameterString intValue];
            if (parameterIsNegative)
                numericParameter = -numericParameter;
            [self _handleKeyword:letterSequence parameter:numericParameter];
            break;
        }
        default:
            [self _handleKeyword:letterSequence];
            break;
    }
}

- (void)_parseHexByte;
{
    UInt8 hexBytes[2];
    CFIndex numBytes = 0;
    hexBytes[numBytes++] = [_scanner scanHexadecimalNumberMaximumDigits:2];

    // Check for double-byte characters
    if (scannerReadString(_scanner, @"\\'"))
        hexBytes[numBytes++] = [_scanner scanHexadecimalNumberMaximumDigits:2];

    CFStringRef byteString = CFStringCreateWithBytes(NULL, hexBytes, numBytes, _currentState->_stringEncoding, NO);
    OBASSERT(byteString != NULL); // Or something went wrong with our string encoding
    if (byteString != NULL) {
        [self _actionAppendString:(NSString *)byteString];
        CFRelease(byteString);
    }
}

- (void)_parseControlSymbol;
{
    unichar controlSymbol = scannerPeekCharacter(_scanner);
    scannerSkipPeekedCharacter(_scanner);

    switch (controlSymbol) {
        case '*':
            [self _actionSkipDestination];
            break;
        case '\'':
            [self _parseHexByte];
            break;
        default:
            [self _actionAppendString:[NSString stringWithCharacter:controlSymbol]];
            break;
    }
}

- (void)_pushRTFState;
{
    OBPRECONDITION(_pushedStates != nil);
    OBPRECONDITION(_currentState != nil);

    OUIRTFReaderState *oldState = _currentState;
    [_pushedStates addObject:oldState];
    _currentState = [oldState copy];
    [oldState release];

    OBPOSTCONDITION(_currentState != nil);
}

- (void)_popRTFState;
{
    OBPRECONDITION(_pushedStates != nil);
    OBPRECONDITION(_currentState != nil);

    [_currentState release];
    
    if ([_pushedStates count] != 0) {
        _currentState = [[_pushedStates lastObject] retain];
        [_pushedStates removeLastObject];
    } else {
        _currentState = [[OUIRTFReaderState alloc] init];
    }

    OBPOSTCONDITION(_currentState != nil);
}

- (void)_parseRTFGroupWithSemicolonAction:(OUIRTFReaderAction *)semicolonAction;
{
    OFCharacterSet *reservedSet;
    if (semicolonAction == NULL)
        reservedSet = StandardReservedSet;
    else
        reservedSet = SemicolonReservedSet;

    NSUInteger pushedStateCount = [_pushedStates count]; // Keep track of our starting depth
    while (scannerHasData(_scanner)) {
        switch (scannerPeekCharacter(_scanner)) {
            case '\\':
                scannerSkipPeekedCharacter(_scanner); // Skip '\'
                unichar controlCharacter = scannerPeekCharacter(_scanner);
                if (OFCharacterSetHasMember(LetterSequenceDelimiters, controlCharacter))
                    [self _parseControlSymbol];
                else
                    [self _parseKeyword];
                break;
            case '{':
                scannerSkipPeekedCharacter(_scanner); // Skip '{'
                [self _pushRTFState];
                break;
            case '}':
                scannerSkipPeekedCharacter(_scanner); // Skip '}'
                [self _popRTFState];
                if ([_pushedStates count] < pushedStateCount)
                    return;
                break;
            case '\r': case '\n':
                // Skip noise
                scannerSkipPeekedCharacter(_scanner);
                break;
            case ';':
                if (semicolonAction != nil) {
                    [semicolonAction performActionWithParser:self];
                    break;
                }
                // Fall through
            default:
                if (_currentState->_flags.discardText) {
                    // Skip all unreserved characters
                    scannerScanUpToCharacterInOFCharacterSet(_scanner, reservedSet);
                } else {
                    // Read all unreserved characters
                    NSString *destinationText = [_scanner readTokenFragmentWithDelimiterOFCharacterSet:reservedSet];
                    [self _actionAppendString:destinationText];
                }
                break;
        }
    }
}

- (void)_parseRTF;
{
    while (scannerHasData(_scanner))
        [self _parseRTFGroupWithSemicolonAction:nil];
}

@end

@implementation OUIRTFReaderState

- (id)init;
{
    if ([super init] == nil)
        return nil;

    _stringEncoding = kCFStringEncodingWindowsLatin1;
    _unicodeSkipCount = 1;
    _fontSize = 12.0f;
    _underline = kCTUnderlineStyleNone;

    [self resetParagraphAttributes];

    return self;
}

- (id)copyWithZone:(NSZone *)zone;
{
    OUIRTFReaderState *copy = (OUIRTFReaderState *)OFCopyObject(self, 0, zone);
    [copy->_alternateDestination retain];
    [copy->_foregroundColor retain];
    copy->_cachedStringAttributes = nil;
    return copy;
}

- (void)dealloc;
{
    [_alternateDestination release];
    [_foregroundColor release];
    [_cachedStringAttributes release];
    [super dealloc];
}

- (void)_resetCache;
{
    [_cachedStringAttributes release];
    _cachedStringAttributes = nil;
}

#pragma mark -
#pragma mark Properties

@synthesize alternateDestination = _alternateDestination;

- (id)foregroundColor;
{
    return _foregroundColor;
}

- (void)setForegroundColor:(id)newColor;
{
    if (_foregroundColor == newColor)
        return;

    [_foregroundColor release];
    _foregroundColor = [newColor retain];

    [self _resetCache];
}

- (CGFloat)fontSize;
{
    return _fontSize;
}

- (void)setFontSize:(CGFloat)newSize;
{
    _fontSize = newSize;

    [self _resetCache];
}

- (int)fontNumber;
{
    return _fontNumber;
}

- (void)setFontNumber:(int)newNumber;
{
    _fontNumber = newNumber;

    [self _resetCache];
}

- (BOOL)bold;
{
    return _flags.bold != 0;
}

- (void)setBold:(BOOL)newSetting;
{
    _flags.bold = newSetting;

    [self _resetCache];
}

- (BOOL)italic;
{
    return _flags.italic != 0;
}

- (void)setItalic:(BOOL)newSetting;
{
    _flags.italic = newSetting;

    [self _resetCache];
}

- (void)setUnderlineStyle:(unsigned)ul
{
    _underline = ul;
    
    [self _resetCache];
}

@synthesize underlineStyle = _underline;

@synthesize fontCharacterSet = _fontCharacterSet;

- (CTTextAlignment)paragraphAlignment;
{
    return _paragraph.alignment;
}

- (void)setParagraphAlignment:(CTTextAlignment)newAlignment;
{
    _paragraph.alignment = newAlignment;

    [self _resetCache];
}

- (int)paragraphFirstLineIndent;
{
    return _paragraph.firstLineIndent;
}

- (void)setParagraphFirstLineIndent:(int)newValue;
{
    _paragraph.firstLineIndent = newValue;

    [self _resetCache];
}

- (int)paragraphLeftIndent;
{
    return _paragraph.leftIndent;
}

- (void)setParagraphLeftIndent:(int)newValue;
{
    _paragraph.leftIndent = newValue;

    [self _resetCache];
}

- (int)paragraphRightIndent;
{
    return _paragraph.rightIndent;
}

- (void)setParagraphRightIndent:(int)newValue;
{
    _paragraph.rightIndent = newValue;

    [self _resetCache];
}

#pragma mark -
#pragma mark API

- (NSMutableDictionary *)stringAttributesForReader:(OUIRTFReader *)reader;
{
    if (_cachedStringAttributes == nil) {
        OMNI_POOL_START {
            _cachedStringAttributes = [[NSMutableDictionary alloc] init];
            if (_foregroundColor != NULL)
                [_cachedStringAttributes setObject:_foregroundColor forKey:(NSString *)kCTForegroundColorAttributeName];
#ifdef DEBUG_RTF_READER
            NSLog(@"-stringAttributes: foregroundColor=%@", [OUIRTFReader debugStringForColor:_foregroundColor]);
#endif
            if ((_underline & 0xFF) != 0)
                [_cachedStringAttributes setUnsignedIntValue:_underline forKey:(NSString *)kCTUnderlineStyleAttributeName];
            NSMutableDictionary *fontAttributes = [[NSMutableDictionary alloc] init];
            [fontAttributes setObject:[reader _fontNameAtIndex:_fontNumber] forKey:(id)kCTFontNameAttribute];
            if (_fontSize > 0.0)
                [fontAttributes setObject:[NSNumber numberWithCGFloat:_fontSize] forKey:(id)kCTFontSizeAttribute];
            OAFontDescriptor *fontDescriptor = [[[OAFontDescriptor alloc] initWithFontAttributes:fontAttributes] autorelease];
            [fontAttributes release];
            if (_flags.bold)
                fontDescriptor = [[fontDescriptor newFontDescriptorWithBold:_flags.bold] autorelease];
            if (_flags.italic)
                fontDescriptor = [[fontDescriptor newFontDescriptorWithItalic:_flags.italic] autorelease];
            OAFontDescriptorPlatformFont font = [fontDescriptor font];
#ifdef DEBUG_RTF_READER
            NSLog(@"-stringAttributes: font=%@", [OUIRTFReader debugStringForFont:font]);
#endif
#ifdef OMNI_ASSERTIONS_ON
            OBASSERT([fontDescriptor bold] == _flags.bold);
            OBASSERT([fontDescriptor italic] == _flags.italic);
            OAFontDescriptor *newFontDescriptor = [[OAFontDescriptor alloc] initWithFont:font];
            OBASSERT([newFontDescriptor bold] == _flags.bold);
            OBASSERT([newFontDescriptor italic] == _flags.italic);
            [newFontDescriptor release];
#endif
            [_cachedStringAttributes setObject:(id)font forKey:(NSString *)kCTFontAttributeName];


            CTTextAlignment alignment = _paragraph.alignment;
            CGFloat firstLineHeadIndent = 1.0f / 20.0f * (_paragraph.leftIndent + _paragraph.firstLineIndent);
            CGFloat headIndent = 1.0f / 20.0f * _paragraph.leftIndent;
            CGFloat tailIndent = 1.0f / 20.0f * (8640 - _paragraph.rightIndent);
            CTParagraphStyleSetting settings[] = {
                {kCTParagraphStyleSpecifierAlignment, sizeof(alignment), &alignment},
                {kCTParagraphStyleSpecifierFirstLineHeadIndent, sizeof(firstLineHeadIndent), &firstLineHeadIndent},
                {kCTParagraphStyleSpecifierHeadIndent, sizeof(headIndent), &headIndent},
                {kCTParagraphStyleSpecifierTailIndent, sizeof(tailIndent), &tailIndent},
            };
            CFIndex settingCount = sizeof(settings) / sizeof(*settings);
            if (_paragraph.rightIndent == NO_RIGHT_INDENT)
                settingCount--;
            CTParagraphStyleRef paragraphStyle = CTParagraphStyleCreate(settings, settingCount);
            [_cachedStringAttributes setObject:(id)paragraphStyle forKey:(NSString *)kCTParagraphStyleAttributeName];
            CFRelease(paragraphStyle);
        } OMNI_POOL_END;
    }

    return _cachedStringAttributes;
}

- (CFStringEncoding)fontEncoding;
{
    #define WIN32_ANSI_CHARSET          0   /* CP1252, ansi-0, iso8859-{1,15} */
    #define WIN32_DEFAULT_CHARSET       1
    #define WIN32_SYMBOL_CHARSET        2
    #define WIN32_SHIFTJIS_CHARSET      128 /* CP932 */
    #define WIN32_HANGEUL_CHARSET       129 /* CP949, ksc5601.1987-0 */
    #define WIN32_HANGUL_CHARSET        HANGEUL_CHARSET
    #define WIN32_GB2312_CHARSET        134 /* CP936, gb2312.1980-0 */
    #define WIN32_CHINESEBIG5_CHARSET   136 /* CP950, big5.et-0 */
    #define WIN32_GREEK_CHARSET         161 /* CP1253 */
    #define WIN32_TURKISH_CHARSET       162 /* CP1254, -iso8859-9 */
    #define WIN32_HEBREW_CHARSET        177 /* CP1255, -iso8859-8 */
    #define WIN32_ARABIC_CHARSET        178 /* CP1256, -iso8859-6 */
    #define WIN32_BALTIC_CHARSET        186 /* CP1257, -iso8859-13 */
    #define WIN32_VIETNAMESE_CHARSET    163 /* CP1258 */
    #define WIN32_RUSSIAN_CHARSET       204 /* CP1251, -iso8859-5 */
    #define WIN32_EE_CHARSET            238 /* CP1250, -iso8859-2 */
    #define WIN32_EASTEUROPE_CHARSET    EE_CHARSET
    #define WIN32_THAI_CHARSET          222 /* CP874, iso8859-11, tis620 */
    #define WIN32_JOHAB_CHARSET         130 /* korean (johab) CP1361 */
    #define WIN32_MAC_CHARSET           77
    #define WIN32_OEM_CHARSET           255

    switch (_fontCharacterSet) {
        default: case WIN32_ANSI_CHARSET: return kCFStringEncodingWindowsLatin1;
        case WIN32_SYMBOL_CHARSET: return kCFStringEncodingMacSymbol;
        case WIN32_SHIFTJIS_CHARSET: return kCFStringEncodingShiftJIS;
        case WIN32_HANGEUL_CHARSET: return kCFStringEncodingDOSKorean;
        case WIN32_GB2312_CHARSET: return kCFStringEncodingDOSChineseSimplif;
        case WIN32_CHINESEBIG5_CHARSET: return kCFStringEncodingDOSChineseTrad;
        case WIN32_GREEK_CHARSET: return kCFStringEncodingWindowsGreek;
        case WIN32_TURKISH_CHARSET: return kCFStringEncodingWindowsLatin5;
        case WIN32_HEBREW_CHARSET: return kCFStringEncodingWindowsHebrew;
        case WIN32_ARABIC_CHARSET: return kCFStringEncodingWindowsArabic;
        case WIN32_BALTIC_CHARSET: return kCFStringEncodingWindowsBalticRim;
        case WIN32_VIETNAMESE_CHARSET: return kCFStringEncodingWindowsVietnamese;
        case WIN32_RUSSIAN_CHARSET: return kCFStringEncodingWindowsCyrillic;
        case WIN32_EE_CHARSET: return kCFStringEncodingWindowsLatin2;
        case WIN32_THAI_CHARSET: return kCFStringEncodingDOSThai;
        case WIN32_JOHAB_CHARSET: return kCFStringEncodingWindowsKoreanJohab;
        case WIN32_MAC_CHARSET: return kCFStringEncodingMacRoman;
    }
}

- (void)resetParagraphAttributes;
{
    _paragraph.alignment = kCTLeftTextAlignment;
    _paragraph.firstLineIndent = 0;
    _paragraph.leftIndent = 0;
    _paragraph.rightIndent = NO_RIGHT_INDENT;

    [self _resetCache];
}

@end

@implementation OUIRTFReaderAction

- (void)performActionWithParser:(OUIRTFReader *)parser;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)performActionWithParser:(OUIRTFReader *)parser parameter:(int)parameter;
{
    OBRequestConcreteImplementation(self, _cmd);
}

@end

@implementation OUIRTFReaderSelectorAction

- (id)initWithSelector:(SEL)selector defaultValue:(int)defaultValue;
{
    if ([super init] == nil)
        return nil;

    _selector = selector;
    _defaultValue = defaultValue;
    Method method = class_getInstanceMethod([OUIRTFReader class], selector);
    if (!method)
        [NSException raise:NSInvalidArgumentException format:@"OUIRTFReader does not respond to the selector %@", NSStringFromSelector(selector)];
    _implementation = method_getImplementation(method);
    _forceValue = NO;

    return self;
}

- (id)initWithSelector:(SEL)selector;
{
    return [self initWithSelector:selector defaultValue:1];
}

- (id)initWithSelector:(SEL)selector value:(int)value;
{
    self = [self initWithSelector:selector defaultValue:value];
    _forceValue = YES;
    return self;
}

- (void)performActionWithParser:(OUIRTFReader *)parser;
{
    _implementation(parser, _selector, _defaultValue);
}

- (void)performActionWithParser:(OUIRTFReader *)parser parameter:(int)parameter;
{
    if (_forceValue) {
        _implementation(parser, _selector, _defaultValue);
        return;
    }

    _implementation(parser, _selector, parameter);
}

@end

@implementation OUIRTFReaderAppendStringAction
{
    NSString *_string;
}

+ (OUIRTFReaderAction *)appendStringActionWithString:(NSString *)string;
{
    return [[[self alloc] initWithString:string] autorelease];
}

- (id)initWithString:(NSString *)string;
{
    if ([super init] == nil)
        return nil;

    _string = [string retain];

    return self;
}

- (void)dealloc;
{
    [_string release];
    [super dealloc];
}

- (void)performActionWithParser:(OUIRTFReader *)parser;
{
    [parser _actionAppendString:_string];
}

- (void)performActionWithParser:(OUIRTFReader *)parser parameter:(int)parameter;
{
    [self performActionWithParser:parser];
}

@end

@implementation OUIRTFReaderFontTableEntry

@synthesize name = _name;
@synthesize encoding = _encoding;

- (void)dealloc;{
    [_name release];
    [super dealloc];
}
@end

