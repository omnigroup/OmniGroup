// Copyright 2005-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLBuffer.h>

#import <OmniFoundation/OFErrors.h>

RCS_ID("$Id$");

// Store a buffer of UTF-8 encoded characters.
struct _OFXMLBuffer {
    size_t used;
    size_t size;
    uint8_t *utf8;
};

OFXMLBuffer OFXMLBufferCreate(void)
{
    return calloc(1, sizeof(struct _OFXMLBuffer));
}

void OFXMLBufferDestroy(OFXMLBuffer buf)
{
    if (buf->utf8)
        free(buf->utf8);
    free(buf);
}

static inline void _OFXMLBufferEnsureSpace(OFXMLBuffer buf, size_t additionalLength)
{
    if (buf->used + additionalLength > buf->size) {
        buf->size = 2 * (buf->used + additionalLength);
        buf->utf8 = (uint8_t *)realloc(buf->utf8, sizeof(*buf->utf8) * buf->size);
    }
}

void OFXMLBufferAppendString(OFXMLBuffer buf, CFStringRef str)
{
    OBPRECONDITION(str);
    if (!str)
	return;
    
    CFIndex characterCount = CFStringGetLength(str);
    
    size_t additionalLength = characterCount * 4; // The maximum size that a unichar can be in UTF-8.
    _OFXMLBufferEnsureSpace(buf, additionalLength);
    
    CFIndex availableSpace = buf->size - buf->used;
    CFIndex usedBufLen = 0;
    
    // Does not zero terminate.
    CFIndex charactersConverted = CFStringGetBytes(str, CFRangeMake(0, characterCount), kCFStringEncodingUTF8, 0/*lossByte; loss not allowed*/, false/*isExternalRepresentation*/,
                                                   &buf->utf8[buf->used], availableSpace, &usedBufLen);
    if (charactersConverted != characterCount) {
        OBASSERT_NOT_REACHED("Everything should be representable in UTF-8 and we should have enough space");
        return;
    }
    
    buf->used += usedBufLen;
}

// TODO: Should probably make callers pass the length (or at least add a variant where they can)
void OFXMLBufferAppendUTF8CString(OFXMLBuffer buf, const char *str)
{
    char c;
    while ((c = *str++)) {
        _OFXMLBufferEnsureSpace(buf, 1);
        buf->utf8[buf->used] = c;
        buf->used++;
    }
}

// Appends the quoted form of the given unquoted string.  We assume the input is valid UTF-8, is NUL terminated and is not already quoted.  This is intended to operate like OFXMLCreateStringWithEntityReferencesInCFEncoding, given a mask of OFXMLBasicEntityMask and an encoding of kCFStringEncodingUTF8. We could use that, except we want to avoid creating temporary objects on this path since it is used to capture sub-element data on the iPhone.
void OFXMLBufferAppendQuotedUTF8CString(OFXMLBuffer buf, const char *unquotedString)
{
    char c;
    while ((c = *unquotedString++)) {
        if ((c & 0x80) == 0) {
            // A 7-bit character.  XML doesn't allow low ASCII characters (see _OFXMLCreateStringWithEntityReferences) other than some specific entries.
            switch (c) {
#define QUOTE_WITH(s) OFXMLBufferAppendUTF8Bytes(buf, s, strlen(s)); break
                case '&': QUOTE_WITH("&amp;");
                case '<': QUOTE_WITH("&lt;");
                case '>': QUOTE_WITH("&gt;");
                case '\'': QUOTE_WITH("&apos;");
                case '"': QUOTE_WITH("&quot;");
#undef QUOTE_WITH
                default:
                    if (c >= 0x20 || c == '\n' || c == '\t' || c == '\r') {
                        _OFXMLBufferEnsureSpace(buf, 1);
                        buf->utf8[buf->used] = c;
                        buf->used++;
                    } else {
                        // This is a low-ascii, non-whitespace byte and isn't allowed in XML character at all.  Drop it.
                        OBASSERT(c < 0x20 && c != 0x9 && c != 0xA && c != 0xD);
                    }
                    break;
            }
        } else {
            // Part of a UTF-8 sequence.  We assume these are valid and just pass them through.
            _OFXMLBufferEnsureSpace(buf, 1);
            buf->utf8[buf->used] = c;
            buf->used++;
        }
    }
}

void OFXMLBufferAppendUTF8Bytes(OFXMLBuffer buf, const char *str, size_t byteCount)
{
    _OFXMLBufferEnsureSpace(buf, byteCount);
    memcpy(&buf->utf8[buf->used], str, byteCount);
    buf->used += byteCount;
}

void OFXMLBufferAppendSpaces(OFXMLBuffer buf, CFIndex count)
{
    _OFXMLBufferEnsureSpace(buf, count);
    
    // Can memset since we are going to a UTF-8 buffer and space is a single byte in UTF-8.
    memset(&buf->utf8[buf->used], ' ', count);
    buf->used += count;
}

void OFXMLBufferAppendUTF8Data(OFXMLBuffer buf, CFDataRef data)
{
    OFXMLBufferAppendUTF8Bytes(buf, (const char *)CFDataGetBytePtr(data), CFDataGetLength(data));
}

CFDataRef OFXMLBufferCopyData(OFXMLBuffer buf, CFStringEncoding encoding)
{
    if (encoding == kCFStringEncodingUTF8)
        return CFDataCreate(kCFAllocatorDefault, buf->utf8, buf->used);
    
    CFStringRef str = CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, buf->utf8, buf->used, kCFStringEncodingUTF8, false/*isExternalRepresentation*/, kCFAllocatorNull/*no free*/);
    OBASSERT(str);
    CFDataRef data = CFStringCreateExternalRepresentation(kCFAllocatorDefault, str, encoding, 0/*lossByte*/);
    OBASSERT(data);
    CFRelease(str);
    return data;
}

CFStringRef OFXMLBufferCopyString(OFXMLBuffer buf)
{
    return CFStringCreateWithBytes(kCFAllocatorDefault, buf->utf8, buf->used, kCFStringEncodingUTF8, false/*isExternalRepresentation*/);
}
