// Copyright 2004-2005, 2007-2008, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniBase/OmniBase.h>

#import <Foundation/NSCharacterSet.h>

RCS_ID("$Id$");

/*" These must match the 'NAME' production in <http://www.w3.org/TR/2004/REC-xml-20040204/>:
 
 NameChar ::= Letter | Digit | '.' | '-' | '_' | ':' | CombiningChar | Extender
 Name     ::= (Letter | '_' | ':') (NameChar)*
 
 NameChar is a production that allows a whole bunch of Unicode crud and I'm not going to type that in!
 "*/

static NSCharacterSet *_InvalidNameChar(void)
{
    static NSCharacterSet *InvalidNC = nil;
    
    if (!InvalidNC) {
        NSMutableCharacterSet *set = [[NSCharacterSet characterSetWithCharactersInString:@".-_:"] mutableCopy];
        [set formUnionWithCharacterSet:[NSCharacterSet alphanumericCharacterSet]];
        InvalidNC = [[set invertedSet] copy];
        [set release];
    }
    return InvalidNC;
}

BOOL OFXMLIsValidID(NSString *identifier)
{
    NSUInteger length = [identifier length];
    if (length == 0)
        return NO;
    
    // The first character can has a more limited set of options than the rest.  No numbers, no '.' and no '-'.
    unichar c = [identifier characterAtIndex:0];
    if (c != '_' && c != ':' && ![[NSCharacterSet letterCharacterSet] characterIsMember:c])
        return NO;
    
    
    NSRange r = [identifier rangeOfCharacterFromSet:_InvalidNameChar() options:0 range:(NSRange){1, length-1}];
    if (r.length > 0)
        return NO;
    return YES;
}

/*" Creates a valid XML 'ID' attribute.  These must match the 'NAME' production in <http://www.w3.org/TR/2004/REC-xml-20040204/>.  We want these to be short but still typically unique.  For example, we don't want two users editing the same file in CVS to create duplicate identifiers.  We can't satisfy both of these goals all the time, but we can make it extremely unlikely.  We'll make our IDs be 64-bits of pseudo data out of encoded via a simple packing.
 "*/

#import <OmniFoundation/OFRandom.h>

// ':' is allowed in all positions, and '.' after the first position.  But as these have meaning on some filesystems, let's not use it in case our ids are used in file names.  This, also means our choice of characters is 64 options.
static const char OFXMLIDCharacter[64] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_";

NSString *OFXMLCreateID(void)
{
    uint64_t value = OFRandomNext64();
    
    // Encoding 64 bits 6 bits at a time yields 11 characters (64/6 == 10 + rem 4).
    char encode[11];
    
    // We'll actually encode 4 of the bits in the first character to ensure that it is a letter (which is required in the XML 'NAME' production).
    encode[0] = OFXMLIDCharacter[value & ((1<<4) - 1)];
    value >>= 4;
    
    unsigned int encodeIndex;
    for (encodeIndex = 1; encodeIndex < 11; encodeIndex++) {
        unsigned char i = value & ((1<<6) - 1);
        encode[encodeIndex] = OFXMLIDCharacter[i];
        value >>= 6;
    }
    
    OBASSERT(value == 0); // should have consumed the whole value at this point
    
    return [[NSString alloc] initWithBytes:encode length:sizeof(encode) encoding:NSASCIIStringEncoding];
}

/*
 A more generic base-64 encoding than OFXMLCreateID (w/o all the cruft from RFC-1521 that would make invalid XML identifiers). This doesn't guarantee different output for different datas in all cases. In particular, if <00 00 00>
 */
NSString *OFXMLCreateIDFromData(NSData *data)
{
    const uint8_t *input = [data bytes];
    NSUInteger inputSize = [data length];
    NSUInteger inputIndex = 0;
    
    if (inputSize == 0)
        return @"";
    
    NSUInteger outputSize = (inputSize*8)/6 + 2; // Add one for only 4 bits in first character and an extra for rounding up. Probably could do the math...
    char *output = malloc(outputSize);
    NSUInteger outputIndex = 0;
    
    // As above, only encode 4 bits in the first character
    uint32_t buffer = input[0];
    uint32_t bitsInBuffer = 8;
    output[0] = OFXMLIDCharacter[buffer & ((1<<4) - 1)];
    buffer >>= 4;
    bitsInBuffer -= 4;
    
    inputIndex++;
    outputIndex++;
    
    // Then process the rest 6 bits at a time.
    while (inputIndex < inputSize || bitsInBuffer > 0) {
        if (bitsInBuffer <= 24 && inputIndex < inputSize) {
            // Room in buffer for 8 more bits
            buffer |= input[inputIndex] << bitsInBuffer;
            inputIndex++;
            bitsInBuffer += 8;
        }
        
        output[outputIndex] = OFXMLIDCharacter[buffer & ((1<<6) - 1)];
        buffer >>= 6;
        bitsInBuffer -= MIN(6UL, bitsInBuffer);
        outputIndex++;
    }
    
    OBASSERT(outputIndex <= outputSize); // No trailing NUL
    return [[NSString alloc] initWithBytesNoCopy:output length:outputIndex encoding:NSASCIIStringEncoding freeWhenDone:YES];
}
