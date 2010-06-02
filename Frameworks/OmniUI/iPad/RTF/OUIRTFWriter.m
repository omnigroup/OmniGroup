// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIRTFWriter.h>

#import <OmniFoundation/OFDataBuffer.h>
#import <OmniFoundation/OFStringScanner.h>
#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <CoreText/CTParagraphStyle.h>
#import <CoreText/CTStringAttributes.h>
#endif

RCS_ID("$Id$");

#ifdef DEBUG_kc0
#define DEBUG_RTF_WRITER
#endif

@interface OUIRTFWriter ()

@property (readwrite, retain) NSAttributedString *attributedString;

- (NSData *)_rtfData;

@end

@interface OUIRTFColorTableEntry : OFObject
{
@private
    int red, green, blue;
}

- (id)initWithColor:(id)color;
- (void)writeToDataBuffer:(OFDataBuffer *)dataBuffer;

@end

@implementation OUIRTFWriter

@synthesize attributedString = _attributedString;

static OFCharacterSet *ReservedSet;

+ (void)initialize;
{
    OBINITIALIZE;

    ReservedSet = [[OFCharacterSet alloc] init];
    [ReservedSet addAllCharacters];
    [ReservedSet removeCharactersInRange:NSMakeRange(32, 127 - 32)]; // Allow the ASCII range of non-control characters
    [ReservedSet addCharactersInString:@"\\{}\r\n"]; // Reserve the few ASCII characters that RTF needs us to quote
}

#ifdef DEBUG_RTF_WRITER

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

#endif

+ (NSData *)rtfDataForAttributedString:(NSAttributedString *)attributedString;
{
    NSData *rtfData = nil;
    OMNI_POOL_START {
        OUIRTFWriter *rtfWriter = [[self alloc] init];
        rtfWriter.attributedString = attributedString;
        rtfData = [[rtfWriter _rtfData] retain];
        [rtfWriter release];
    } OMNI_POOL_END;
    return [rtfData autorelease];
}

- (id)init;
{
    _state.fontSize = -1;
    _state.fontIndex = -1;
    _state.colorIndex = -1;
    _state.underline = kCTUnderlineStyleNone;
    _dataBuffer = malloc(sizeof(OFDataBuffer));
    OFDataBufferInit(_dataBuffer);
    return self;
}

- (void)dealloc;
{
    [_attributedString release];
    [_registeredColors release];
    [_registeredFonts release];
    OFDataBufferRelease(_dataBuffer); free(_dataBuffer); _dataBuffer = NULL;

    [super dealloc];
}

static const struct {
    const char *name;
    unsigned int ctValue;
} underlineStyleKeywords[] = {
    { "uld", kCTUnderlineStyleSingle|kCTUnderlinePatternDot },
    { "uldash", kCTUnderlineStyleSingle|kCTUnderlinePatternDash },
    { "uldashd", kCTUnderlineStyleSingle|kCTUnderlinePatternDashDot },
    { "uldashdd", kCTUnderlineStyleSingle|kCTUnderlinePatternDashDotDot },
    { "uldb", kCTUnderlineStyleDouble },
    { "ulth", kCTUnderlineStyleThick },
    { "ulthd", kCTUnderlineStyleThick|kCTUnderlinePatternDot },
    { "ulthdash", kCTUnderlineStyleThick|kCTUnderlinePatternDash },
    { "ulthdashd", kCTUnderlineStyleThick|kCTUnderlinePatternDashDot },
    { "ulthdashdd", kCTUnderlineStyleThick|kCTUnderlinePatternDashDotDot },
    { NULL, 0 },
};

- (void)_writeFontAttributes:(NSDictionary *)newAttributes;
{
    OAFontDescriptorPlatformFont newPlatformFont = (OAFontDescriptorPlatformFont)[newAttributes objectForKey:(NSString *)kCTFontAttributeName];
    OAFontDescriptor *newFontDescriptor;
    if (newPlatformFont == nil)
        newFontDescriptor = [[OAFontDescriptor alloc] initWithFamily:@"Helvetica" size:12.0f];
    else
        newFontDescriptor = [[OAFontDescriptor alloc] initWithFont:newPlatformFont];
    int newFontSize = (int)round([newFontDescriptor size] * 2.0);
    NSNumber *newFontIndexValue = [_registeredFonts objectForKey:[newFontDescriptor fontName]];
    OBASSERT(newFontIndexValue != nil);
    int newFontIndex = [newFontIndexValue intValue];
    BOOL newFontBold = [newFontDescriptor bold];
    BOOL newFontItalic = [newFontDescriptor italic];
    [newFontDescriptor release];
    unsigned int newUnderline = [newAttributes unsignedIntForKey:(NSString *)kCTUnderlineStyleAttributeName defaultValue:kCTUnderlineStyleNone];
    
    BOOL shouldWriteNewFontSize;
    BOOL shouldWriteNewFontIndex;
    BOOL shouldWriteNewFontBold;
    BOOL shouldWriteNewFontItalic;
    BOOL needTerminatingSpace = NO;

    if (_state.fontIndex == -1) {
        shouldWriteNewFontIndex = YES;
        shouldWriteNewFontSize = YES;
        shouldWriteNewFontBold = newFontBold;
        shouldWriteNewFontItalic = newFontItalic;
    } else {
        shouldWriteNewFontIndex = newFontIndex != _state.fontIndex;
        shouldWriteNewFontSize = newFontSize != _state.fontSize;
        shouldWriteNewFontBold = newFontBold != _state.flags.bold;
        shouldWriteNewFontItalic = newFontItalic != _state.flags.italic;
    }

    if (shouldWriteNewFontIndex) {
        OFDataBufferAppendCString(_dataBuffer, "\\f");
        OFDataBufferAppendInteger(_dataBuffer, newFontIndex);
        needTerminatingSpace = YES;
        _state.fontIndex = newFontIndex;
    }

    if (shouldWriteNewFontSize) {
        OFDataBufferAppendCString(_dataBuffer, "\\fs");
        OFDataBufferAppendInteger(_dataBuffer, newFontSize);
        needTerminatingSpace = YES;
        _state.fontSize = newFontSize;
    }

    if (shouldWriteNewFontBold) {
        if (newFontBold)
            OFDataBufferAppendCString(_dataBuffer, "\\b");
        else
            OFDataBufferAppendCString(_dataBuffer, "\\b0");
        needTerminatingSpace = YES;
        _state.flags.bold = newFontBold;
    }

    if (shouldWriteNewFontItalic) {
        if (newFontItalic)
            OFDataBufferAppendCString(_dataBuffer, "\\i");
        else
            OFDataBufferAppendCString(_dataBuffer, "\\i0");
        needTerminatingSpace = YES;
        _state.flags.italic = newFontItalic;
    }
    
    if (newUnderline != _state.underline) {
        if ((newUnderline & 0xFF) == kCTUnderlineStyleNone) {
            // Special case
            OFDataBufferAppendCString(_dataBuffer, "\\ul0");
        } else {
            int styleIndex;
            for(styleIndex = 0; underlineStyleKeywords[styleIndex].name != NULL; styleIndex ++) {
                if (underlineStyleKeywords[styleIndex].ctValue == newUnderline)
                    break;
            }
            if (underlineStyleKeywords[styleIndex].name == NULL) {
                // Fallback to plain ol' underline
                OFDataBufferAppendCString(_dataBuffer, "\\ul");
            } else {
                OFDataBufferAppendByte(_dataBuffer, '\\');
                OFDataBufferAppendCString(_dataBuffer, underlineStyleKeywords[styleIndex].name);
            }
        }
        
        needTerminatingSpace = YES;
        _state.underline = newUnderline;
    }    

    if (needTerminatingSpace)
        OFDataBufferAppendByte(_dataBuffer, ' ');
}

- (void)_writeColorAttributes:(NSDictionary *)newAttributes;
{
    id newColor = [newAttributes objectForKey:(NSString *)kCTForegroundColorAttributeName];
    OUIRTFColorTableEntry *colorTableEntry = [[OUIRTFColorTableEntry alloc] initWithColor:newColor];
    NSNumber *newColorIndexValue = [_registeredColors objectForKey:colorTableEntry];
    [colorTableEntry release];
    OBASSERT(newColorIndexValue != nil);
    int newColorIndex = [newColorIndexValue intValue];

    if (newColorIndex == _state.colorIndex)
        return;

    OFDataBufferAppendCString(_dataBuffer, "\\cf");
    OFDataBufferAppendInteger(_dataBuffer, newColorIndex);
    OFDataBufferAppendByte(_dataBuffer, ' ');
    _state.colorIndex = newColorIndex;
}

- (void)_writeParagraphAttributes:(NSDictionary *)newAttributes;
{
    CTParagraphStyleRef paragraphStyle = (CTParagraphStyleRef)[newAttributes objectForKey:(id)kCTParagraphStyleAttributeName];
    CTTextAlignment alignment = kCTNaturalTextAlignment;
    CGFloat firstLineHeadIndent = 0.0f, headIndent = 0.0f, tailIndent = 0.0f;
    CTParagraphStyleGetValueForSpecifier(paragraphStyle, kCTParagraphStyleSpecifierAlignment, sizeof(alignment), &alignment);
    CTParagraphStyleGetValueForSpecifier(paragraphStyle, kCTParagraphStyleSpecifierFirstLineHeadIndent, sizeof(firstLineHeadIndent), &firstLineHeadIndent);
    CTParagraphStyleGetValueForSpecifier(paragraphStyle, kCTParagraphStyleSpecifierHeadIndent, sizeof(headIndent), &headIndent);
    CTParagraphStyleGetValueForSpecifier(paragraphStyle, kCTParagraphStyleSpecifierTailIndent, sizeof(tailIndent), &tailIndent);
    
    BOOL needTerminatingSpace = NO;
    int leftIndent = (int)(20.0 * headIndent);
    int firstLineIndent = ((int)(20.0 * firstLineHeadIndent)) - leftIndent;
    int rightIndent = 8640 - (int)(20.0 * tailIndent);
    if (alignment != _state.alignment) {
        switch (alignment) {
            default:
            case kCTNaturalTextAlignment:
            case kCTLeftTextAlignment:
                OFDataBufferAppendCString(_dataBuffer, "\\ql");
                break;
            case kCTRightTextAlignment:
                OFDataBufferAppendCString(_dataBuffer, "\\qr");
                break;
            case kCTCenterTextAlignment:
                OFDataBufferAppendCString(_dataBuffer, "\\qc");
                break;
            case kCTJustifiedTextAlignment:
                OFDataBufferAppendCString(_dataBuffer, "\\qj");
                break;
        }
        _state.alignment = alignment;
        needTerminatingSpace = YES;
    }
    if (firstLineIndent != _state.firstLineIndent) {
        OFDataBufferAppendCString(_dataBuffer, "\\fi");
        OFDataBufferAppendInteger(_dataBuffer, firstLineIndent);
        _state.firstLineIndent = firstLineIndent;
        needTerminatingSpace = YES;
    }
    if (leftIndent != _state.leftIndent) {
        OFDataBufferAppendCString(_dataBuffer, "\\li");
        OFDataBufferAppendInteger(_dataBuffer, leftIndent);
        _state.leftIndent = leftIndent;
        needTerminatingSpace = YES;
    }
    if (rightIndent != _state.rightIndent) {
        OFDataBufferAppendCString(_dataBuffer, "\\ri");
        OFDataBufferAppendInteger(_dataBuffer, rightIndent);
        _state.rightIndent = rightIndent;
        needTerminatingSpace = YES;
    }
    if (needTerminatingSpace)
        OFDataBufferAppendByte(_dataBuffer, '\n');
}

- (void)_writeAttributes:(NSDictionary *)newAttributes beginningOfParagraph:(BOOL)beginningOfParagraph;
{
    OMNI_POOL_START {
        [self _writeFontAttributes:newAttributes];
        [self _writeColorAttributes:newAttributes];
        if (beginningOfParagraph)
            [self _writeParagraphAttributes:newAttributes];
    } OMNI_POOL_END;
}

- (void)_writeColorTable;
{
    _registeredColors = [[NSMutableDictionary alloc] init];

    OFDataBufferAppendCString(_dataBuffer, "{\\colortbl");

    int colorIndex = 0;
    OUIRTFColorTableEntry *defaultColorEntry = [[OUIRTFColorTableEntry alloc] init];
    [_registeredColors setObject:[NSNumber numberWithInt:colorIndex++] forKey:defaultColorEntry];
    [defaultColorEntry writeToDataBuffer:_dataBuffer];
    [defaultColorEntry release];

    NSRange effectiveRange;
    NSUInteger stringLength = [_attributedString length];
    for (NSUInteger textIndex = 0; textIndex < stringLength; textIndex = NSMaxRange(effectiveRange)) {
        id color = [_attributedString attribute:(NSString *)kCTForegroundColorAttributeName atIndex:textIndex effectiveRange:&effectiveRange];
#ifdef DEBUG_RTF_WRITER
        NSLog(@"Registering color: %@", [OUIRTFWriter debugStringForColor:color]);
#endif
        OUIRTFColorTableEntry *colorTableEntry = [[OUIRTFColorTableEntry alloc] initWithColor:color];
        if ([_registeredColors objectForKey:colorTableEntry] == nil) {
            [colorTableEntry writeToDataBuffer:_dataBuffer];
            [_registeredColors setObject:[NSNumber numberWithInt:colorIndex++] forKey:colorTableEntry];
        }
        [colorTableEntry release];
    }
    OFDataBufferAppendCString(_dataBuffer, "}\n");
}

static inline void writeCharacter(OFDataBuffer *dataBuffer, unichar aCharacter)
{
    if (!OFCharacterSetHasMember(ReservedSet, aCharacter)) {
        OBASSERT(aCharacter < 128); // Or it should have been in the reserved set: it can't be written in a single byte as we're about to do
        OFDataBufferAppendByte(dataBuffer, aCharacter);
    } else if (aCharacter < 128) {
        // Write reserved ASCII character
        OFDataBufferAppendByte(dataBuffer, '\\');
        OFDataBufferAppendByte(dataBuffer, aCharacter);
    } else {
        // Write Unicode character
        OFDataBufferAppendCString(dataBuffer, "\\uc0\\u");
        OFDataBufferAppendInteger(dataBuffer, aCharacter);
        OFDataBufferAppendByte(dataBuffer, ' ');
    }
}

static inline void writeString(OFDataBuffer *dataBuffer, NSString *string)
{
    NSUInteger characterCount = [string length];
    unichar *characters = malloc(characterCount * sizeof(unichar));
    [string getCharacters:characters];
    for (NSUInteger characterIndex = 0; characterIndex < characterCount; characterIndex++) {
        writeCharacter(dataBuffer, characters[characterIndex]);
    }
    free(characters);
}

- (void)_writeFontTableEntryWithIndex:(int)fontIndex name:(NSString *)name;
{
    OFDataBufferAppendCString(_dataBuffer, "\\f");
    OFDataBufferAppendInteger(_dataBuffer, fontIndex);
    OFDataBufferAppendCString(_dataBuffer, "\\fnil\\fcharset0 ");
    writeString(_dataBuffer, name);
    OFDataBufferAppendByte(_dataBuffer, ';');
}

- (void)_writeFontTable;
{
    _registeredFonts = [[NSMutableDictionary alloc] init];

    OFDataBufferAppendCString(_dataBuffer, "{\\fonttbl");

    int fontIndex = 0;

    NSRange effectiveRange;
    NSUInteger stringLength = [_attributedString length];
    for (NSUInteger textIndex = 0; textIndex < stringLength; textIndex = NSMaxRange(effectiveRange)) {
        OAFontDescriptorPlatformFont platformFont = (OAFontDescriptorPlatformFont)[_attributedString attribute:(NSString *)kCTFontAttributeName atIndex:textIndex effectiveRange:&effectiveRange];
        NSString *fontName;
        if (platformFont != nil) {
            OAFontDescriptor *fontDescriptor = [[OAFontDescriptor alloc] initWithFont:platformFont];
            fontName = [fontDescriptor fontName];
            [fontDescriptor release];
        } else {
            fontName = @"Helvetica";
        }
        if ([_registeredFonts objectForKey:fontName] == nil) {
#ifdef DEBUG_RTF_WRITER
            NSLog(@"Registering font %d: %@", fontIndex, fontName);
#endif
            [self _writeFontTableEntryWithIndex:fontIndex name:fontName];
            [_registeredFonts setObject:[NSNumber numberWithInt:fontIndex++] forKey:fontName];
        }
    }
    OFDataBufferAppendCString(_dataBuffer, "}\n");
}

- (NSData *)_rtfData;
{
    OFDataBufferAppendCString(_dataBuffer, "{\\rtf1\\ansi\n");

    [self _writeFontTable];
    [self _writeColorTable];

    NSString *string = [_attributedString string];
    OFStringScanner *scanner = [[OFStringScanner alloc] initWithString:string];
    NSRange stringRange = NSMakeRange(0, [string length]);
    NSUInteger scanLocation = 0;
    NSRange currentAttributesRange = NSMakeRange(0, 0);
    BOOL beginningOfParagraph = YES;
    while (scannerHasData(scanner)) {
        OBASSERT(scanLocation == scannerScanLocation(scanner)); // Optimization: we increment our scanLocation each time we skip peeked characters
        if (scanLocation >= NSMaxRange(currentAttributesRange)) {
            NSRange newAttributesRange;
            NSDictionary *newAttributes = [_attributedString attributesAtIndex:scanLocation longestEffectiveRange:&newAttributesRange inRange:stringRange];
            [self _writeAttributes:newAttributes beginningOfParagraph:beginningOfParagraph];
            currentAttributesRange = newAttributesRange;
        }
        
        unichar nextCharacter = scannerPeekCharacter(scanner);
        writeCharacter(_dataBuffer, nextCharacter);
        scannerSkipPeekedCharacter(scanner);
        scanLocation++;
        beginningOfParagraph = (nextCharacter == '\n');
    }
    [scanner release];

    OFDataBufferAppendCString(_dataBuffer, "}");
    NSData *data = [OFDataBufferData(_dataBuffer) retain];
    OFDataBufferRelease(_dataBuffer);
    return [data autorelease];
}

@end

@implementation OUIRTFColorTableEntry

- (id)initWithColor:(id)color;
{
    if (color == nil)
        return self;

    CGColorRef cgColor = (CGColorRef)color;
    CGColorSpaceRef colorSpace = CGColorGetColorSpace(cgColor);
    const CGFloat *components = CGColorGetComponents(cgColor);
    switch (CGColorSpaceGetModel(colorSpace)) {
        case kCGColorSpaceModelMonochrome: {
            OBASSERT(CGColorSpaceGetNumberOfComponents(colorSpace) == 1);
            OBASSERT(CGColorGetNumberOfComponents(cgColor) == 2);
            red = green = blue = (int)round(components[0] * 255.0f);
            break;
        }
        case kCGColorSpaceModelRGB: {
            OBASSERT(CGColorSpaceGetNumberOfComponents(colorSpace) == 3);
            OBASSERT(CGColorGetNumberOfComponents(cgColor) == 4);
            red = (int)round(components[0] * 255.0f);
            green = (int)round(components[1] * 255.0);
            blue = (int)round(components[2] * 255.0);
            break;
        }
        default: {
            NSLog(@"color = %@ %@", color, cgColor);
            NSLog(@"colorSpace %@", colorSpace);
            OBFinishPorting;
        }
    }
    return self;
}

- (void)writeToDataBuffer:(OFDataBuffer *)dataBuffer;
{
    if (red != 0 || green != 0 || blue != 0) {
        OFDataBufferAppendCString(dataBuffer, "\\red");
        OFDataBufferAppendInteger(dataBuffer, red);
        OFDataBufferAppendCString(dataBuffer, "\\green");
        OFDataBufferAppendInteger(dataBuffer, green);
        OFDataBufferAppendCString(dataBuffer, "\\blue");
        OFDataBufferAppendInteger(dataBuffer, blue);
    }
    OFDataBufferAppendByte(dataBuffer, ';');
}

#pragma mark -
#pragma mark NSObject protocol

- (BOOL)isEqual:(id)object;
{
    OUIRTFColorTableEntry *otherEntry = object;
    if (otherEntry->isa != isa)
        return NO;
    return otherEntry->red == red && otherEntry->green == green && otherEntry->blue == blue;
}

- (NSUInteger)hash;
{
    return (red << 16) | (green << 8) | blue;
}

- (id)copyWithZone:(NSZone *)zone;
{
    // We are immutable!
    return [self retain];
}

@end
