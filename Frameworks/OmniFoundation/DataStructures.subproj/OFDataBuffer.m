// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDataBuffer.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

//
// XML Support
//

// TODO -- This assumes that the string can be encoding in ASCII.  We should
// instead support UTF-8.  The problem is that copying characters to the 
// destination buffer becomes a little more difficult (since you'd have
// to copy bytes until getting to the end of a variable length character).
// Not too hard, but I'm not gonna do it just yet.

static inline const OFByte *
_OFDataBufferGetXMLStringPointer(CFStringRef string)
{
    const OFByte *ptr;
    
    if ((ptr = (const OFByte *)CFStringGetCStringPtr(string, kCFStringEncodingMacRoman)))
        return ptr;
//    fprintf(stderr, "Is not MacRoman/CString\n");
    
    if ((ptr = (const OFByte *)CFStringGetPascalStringPtr(string, kCFStringEncodingMacRoman)))
        return ptr + 1;
//    fprintf(stderr, "Is not MacRoman/Pascal\n");
    
    if ((ptr = (const OFByte *)CFStringGetCStringPtr(string, kCFStringEncodingASCII)))
        return ptr;
//    fprintf(stderr, "Is not ASCII/CString\n");
    
    if ((ptr = (const OFByte *)CFStringGetPascalStringPtr(string, kCFStringEncodingASCII)))
        return ptr + 1;
//    fprintf(stderr, "Is not ASCII/Pascal\n");
    
    return NULL;
}

void OFDataBufferAppendXMLQuotedString(OFDataBuffer *dataBuffer, CFStringRef string)
{
    OBPRECONDITION(string);
    
    NSUInteger characterIndex, characterCount = CFStringGetLength(string);

    // If everything is quoted, we could end up with N * characterCount bytes
    // where N = MAX(MaxUTF8CharacterLength, MaxEntityLength).
    OFByte *dest = OFDataBufferGetPointer(dataBuffer, sizeof("&#xffff;") * characterCount);

    const OFByte *source = _OFDataBufferGetXMLStringPointer(string);
    OFByte *ptr;
    if (source) {
        ptr = dest;
        for (characterIndex = 0; characterIndex < characterCount; characterIndex++, source++) {
            OFByte c;
            
            switch ((c = *source)) {
                case '<':
                    *ptr++ = '&';
                    *ptr++ = '#';
                    *ptr++ = '6';
                    *ptr++ = '0';
                    *ptr++ = ';';
                    break;
                case '>':
                    *ptr++ = '&';
                    *ptr++ = '#';
                    *ptr++ = '6';
                    *ptr++ = '2';
                    *ptr++ = ';';
                    break;
                case '&':
                    *ptr++ = '&';
                    *ptr++ = '#';
                    *ptr++ = '3';
                    *ptr++ = '8';
                    *ptr++ = ';';
                    break;
                case '\'':
                    *ptr++ = '&';
                    *ptr++ = '#';
                    *ptr++ = '3';
                    *ptr++ = '9';
                    *ptr++ = ';';
                    break;
                case '"':
                    *ptr++ = '&';
                    *ptr++ = '#';
                    *ptr++ = '3';
                    *ptr++ = '4';
                    *ptr++ = ';';
                    break;
                default:
                    *ptr++ = c;
                    break;
            }
        }
    } else {
        // Handle other codings.  We'll use a slower but easier approach since the vast
        // majority of strings we see are ASCII or MacRoman
        UniChar *buffer, *src;
        
        buffer = NSZoneMalloc(NULL, sizeof(*buffer) * characterCount);
        src = buffer;
        ptr = dest;
        CFStringGetCharacters(string, CFRangeMake(0, characterCount), buffer);
        for (characterIndex = 0; characterIndex < characterCount; characterIndex++, src++) {
            UniChar c;
            
            switch ((c = *src)) {
                case '<':
                    *ptr++ = '&';
                    *ptr++ = '#';
                    *ptr++ = '6';
                    *ptr++ = '0';
                    *ptr++ = ';';
                    break;
                case '>':
                    *ptr++ = '&';
                    *ptr++ = '#';
                    *ptr++ = '6';
                    *ptr++ = '2';
                    *ptr++ = ';';
                    break;
                case '&':
                    *ptr++ = '&';
                    *ptr++ = '#';
                    *ptr++ = '3';
                    *ptr++ = '8';
                    *ptr++ = ';';
                    break;
                case '\'':
                    *ptr++ = '&';
                    *ptr++ = '#';
                    *ptr++ = '3';
                    *ptr++ = '9';
                    *ptr++ = ';';
                    break;
                case '"':
                    *ptr++ = '&';
                    *ptr++ = '#';
                    *ptr++ = '3';
                    *ptr++ = '4';
                    *ptr++ = ';';
                    break;
                // case ranges weren't working for me for some reason
                default:
                    //fprintf(stderr, "Encoding 0x%04x\n", c);
                    if (c < 0x7f) {
                        *ptr++ = c;
                    } else if (c < 0xff) {
                        *ptr++ = '&';
                        *ptr++ = '#';
                        *ptr++ = 'x';
                        *ptr++ = OFDataBufferHexCharacterForDigit((c & 0xf0) >> 4);
                        *ptr++ = OFDataBufferHexCharacterForDigit((c & 0x0f) >> 0);
                        *ptr++ = ';';
                    } else {
                        *ptr++ = '&';
                        *ptr++ = '#';
                        *ptr++ = 'x';
                        *ptr++ = OFDataBufferHexCharacterForDigit((c & 0xf000) >> 12);
                        *ptr++ = OFDataBufferHexCharacterForDigit((c & 0x0f00) >>  8);
                        *ptr++ = OFDataBufferHexCharacterForDigit((c & 0x00f0) >>  4);
                        *ptr++ = OFDataBufferHexCharacterForDigit((c & 0x000f) >>  0);
                        *ptr++ = ';';
                    }
                    break;
            }
        }
        
        NSZoneFree(NULL, buffer);
    }
    
    OFDataBufferDidAppend(dataBuffer, ptr - dest);
}

