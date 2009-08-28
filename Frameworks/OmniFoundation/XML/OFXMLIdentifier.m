// Copyright 2004-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <OmniFoundation/OFXMLIdentifier.h>

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
    unsigned int length = [identifier length];
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

NSString *OFXMLCreateID(void)
{
    static OFRandomState State;
    static BOOL initialized = NO;
    
    if (!initialized) {
        initialized = YES;
        OFRandomSeed(&State, OFRandomGenerateRandomSeed());
    }
    
    uint32_t low  = OFRandomNextState(&State);
    uint32_t high = OFRandomNextState(&State);
    uint64_t value = (((uint64_t)high) << 32) | low;
    
    
    // ':' is allowed in all positions, and '.' after the first position.  But as these have meaning on some filesystems, let's not use it in case our ids are used in file names.  This, also means our choice of characters is 64 options.
    static const char chars[64] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_";
    
    // Encoding 64 bits 6 bits at a time yields 11 characters (64/6 == 10 + rem 4).
    char encode[11];
    
    // We'll actually encode 4 of the bits in the first character to ensure that it is a letter (which is required in the XML 'NAME' production).
    encode[0] = chars[value & ((1<<4) - 1)];
    value >>= 4;
    
    unsigned int encodeIndex;
    for (encodeIndex = 1; encodeIndex < 11; encodeIndex++) {
        unsigned char i = value & ((1<<6) - 1);
        encode[encodeIndex] = chars[i];
        value >>= 6;
    }
    
    OBASSERT(value == 0); // should have consumed the whole value at this point
    
    return [[NSString alloc] initWithBytes:encode length:sizeof(encode) encoding:NSASCIIStringEncoding];
}
