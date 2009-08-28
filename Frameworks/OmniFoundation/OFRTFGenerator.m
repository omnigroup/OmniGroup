// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRTFGenerator.h>

#import <OmniFoundation/NSString-OFExtensions.h>

RCS_ID("$Id$")

@implementation OFRTFGenerator

- init
{
    OFDataBufferInit(&rtfBuffer);
    OFDataBufferInit(&asciiBuffer);
    fontNames = [[NSMutableArray alloc] init];
    fontNameToNumberDictionary = [[NSMutableDictionary alloc] init];

    wantState.fontNumber = NSNotFound;
    wantState.fontSize = 0;
    wantState.flags.bold = NO;
    wantState.flags.italic = NO;
    wantState.superscript = 0;

    outputState.fontNumber = NSNotFound;
    outputState.fontSize = 0;
    outputState.flags.bold = NO;
    outputState.flags.italic = NO;
    outputState.superscript = 0;
    return self;
}

- (void)dealloc;
{
    OFDataBufferRelease(&rtfBuffer);
    OFDataBufferRelease(&asciiBuffer);
    [fontNames release];
    [fontNameToNumberDictionary release];
    [super dealloc];
}


// Get data

- (NSData *)rtfData;
{
    NSMutableData *rtfData;
    NSMutableString *headerString;
    unsigned int fontIndex, fontCount;

    OFDataBufferSizeToFit(&rtfBuffer);

    rtfData = [NSMutableData dataWithCapacity:[OFDataBufferData(&rtfBuffer) length] + 256];

    headerString = [[NSMutableString alloc] initWithCapacity:256];
    [headerString appendString:@"{\\rtf1\\mac\\ansicpg10000{\\fonttbl"];
    fontCount = [fontNames count];
    for (fontIndex = 0; fontIndex < fontCount; fontIndex++) {
        NSString *fontName, *fontDescriptor;

        fontName = [fontNames objectAtIndex:fontIndex];
        if ([fontName isEqualToString:@"Symbol"]) {
            fontDescriptor = @"\\ftech\\fcharset2";
        } else {
            fontDescriptor = @"\\fnil";
        }        
        [headerString appendFormat:@"\\f%d%@ %@;", fontIndex, fontDescriptor, fontName];
    }
    [headerString appendString:@"}\n"];
    [rtfData appendData:[headerString dataUsingEncoding:NSASCIIStringEncoding]];
    [headerString release];

    [rtfData appendData:OFDataBufferData(&rtfBuffer)];
    [rtfData appendBytes:"\n}" length:2];
    return rtfData;
}

- (NSData *)asciiData;
{
    OFDataBufferSizeToFit(&asciiBuffer);
    return [[OFDataBufferData(&asciiBuffer) retain] autorelease];
}

- (NSString *)asciiString;
{
    return [NSString stringWithData:[self asciiData] encoding:NSMacOSRomanStringEncoding];
}

/*
 * Setting RTF state
 */

- (void)setFontName:(NSString *)fontName;
{
    NSNumber *fontNumberObject;

    fontNumberObject = [fontNameToNumberDictionary objectForKey:fontName];
    if (fontNumberObject)
        wantState.fontNumber = [fontNumberObject intValue];
    else {
        wantState.fontNumber = [fontNames count];
        [fontNames addObject:fontName];
        [fontNames addObject:@"Symbol"];
        [fontNameToNumberDictionary setObject:[NSNumber numberWithInt:wantState.fontNumber] forKey:fontName];
    }

    if (wantState.fontNumber == outputState.fontNumber)
        return;
    hasUnemittedState = YES;
}

- (void)setFontSize:(int)fontSize;
{
    wantState.fontSize = MAX(1, fontSize);
    if (wantState.fontSize == outputState.fontSize)
        return;
    hasUnemittedState = YES;
}

- (void)setBold:(BOOL)flag;
{
    wantState.flags.bold = flag;
    if (wantState.flags.bold == outputState.flags.bold)
        return;
    hasUnemittedState = YES;
}

- (void)setItalic:(BOOL)flag;
{
    wantState.flags.italic = flag;
    if (wantState.flags.italic == outputState.flags.italic)
        return;
    hasUnemittedState = YES;
}

- (void)setSuperscript:(int)superscript;
{
    wantState.superscript = superscript;
    if (wantState.superscript == outputState.superscript)
        return;
    hasUnemittedState = YES;
}

- (void)emitStateChange;
{
    if (!hasUnemittedState)
        return;

    if (wantState.fontNumber != outputState.fontNumber) {
        OFDataBufferAppendCString(&rtfBuffer, "\\f");
        OFDataBufferAppendInteger(&rtfBuffer, wantState.fontNumber);
        OFDataBufferAppendByte(&rtfBuffer, ' ');
        outputState.fontNumber = wantState.fontNumber;
    }
    if (wantState.fontSize != outputState.fontSize) {
        OFDataBufferAppendCString(&rtfBuffer, "\\fs");
        OFDataBufferAppendInteger(&rtfBuffer, wantState.fontSize * 2);
        OFDataBufferAppendByte(&rtfBuffer, ' ');
        outputState.fontSize = wantState.fontSize;
    }
    if (wantState.flags.bold != outputState.flags.bold) {
        OFDataBufferAppendCString(&rtfBuffer, "\\b");
        if (!wantState.flags.bold)
            OFDataBufferAppendInteger(&rtfBuffer, 0);
        OFDataBufferAppendByte(&rtfBuffer, ' ');
        outputState.flags.bold = wantState.flags.bold;
    }
    if (wantState.flags.italic != outputState.flags.italic) {
        OFDataBufferAppendCString(&rtfBuffer, "\\i");
        if (!wantState.flags.italic)
            OFDataBufferAppendInteger(&rtfBuffer, 0);
        OFDataBufferAppendByte(&rtfBuffer, ' ');
        outputState.flags.italic = wantState.flags.italic;
    }
    if (wantState.superscript != outputState.superscript) {
        int upAmount;
        int downAmount;

        if (outputState.superscript == wantState.superscript)
            return;

        upAmount = 0;
        downAmount = 0;
        if (outputState.superscript >= 0) {
            if (wantState.superscript >= 0)
                upAmount = wantState.superscript - outputState.superscript;
            else {
                upAmount = -outputState.superscript;
                downAmount = -wantState.superscript;
            }
        } else {
            if (wantState.superscript < 0)
                downAmount = -(wantState.superscript
                               - outputState.superscript);
            else {
                downAmount = outputState.superscript;
                upAmount = wantState.superscript;
            }
        }
        if (upAmount) {
            OFDataBufferAppendCString(&rtfBuffer, "\\up");
            OFDataBufferAppendInteger(&rtfBuffer, upAmount * 2);
        }
        if (downAmount) {
            OFDataBufferAppendCString(&rtfBuffer, "\\dn");
            OFDataBufferAppendInteger(&rtfBuffer, downAmount * 2);
        }

        outputState.superscript = wantState.superscript;
    }
    hasUnemittedState = NO;
}

// Adding strings

- (void)appendString:(NSString *)string;
{
    [self appendData:[string dataUsingEncoding:NSMacOSRomanStringEncoding allowLossyConversion:YES]];
}

- (void)appendData:(NSData *)data;
{
    [self appendBytes:[data bytes] length:[data length]];
}

- (void)appendBytes:(const unsigned char *)bytes length:(unsigned int)length;
{
    unsigned int byteIndex;

    for (byteIndex = 0; byteIndex < length; byteIndex++)
        rtfAppendUnprocessedCharacter(self, bytes[byteIndex]);
}

@end
