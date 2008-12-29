// Copyright 2005-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLBuffer.h>

#import <OmniFoundation/OFErrors.h>

RCS_ID("$Id$");


struct _OFXMLBuffer {
    unsigned int   length;
    unsigned int   size;
    unichar       *characters;
};

/*
 TODO: Instead of storing Unicode internally, it would be good to store UTF-8.  One question with that is how to implement OFXMLBufferAppendString efficiently, though.
 */

OFXMLBuffer OFXMLBufferCreate(void)
{
    return calloc(1, sizeof(struct _OFXMLBuffer));
}

void OFXMLBufferDestroy(OFXMLBuffer buf)
{
    if (buf->characters)
        free(buf->characters);
    free(buf);
}

static inline void _OFXMLBufferEnsureSpace(OFXMLBuffer buf, CFIndex additionalLength)
{
    if (buf->length + additionalLength > buf->size) {
        buf->size = 2 * (buf->length + additionalLength);
        buf->characters = (unichar *)realloc(buf->characters, sizeof(*buf->characters) * buf->size);
    }
}

void OFXMLBufferAppendString(OFXMLBuffer buf, CFStringRef str)
{
    OBPRECONDITION(str);
    if (!str)
	return;
    
    unsigned additionalLength = CFStringGetLength(str);
    _OFXMLBufferEnsureSpace(buf, additionalLength);
    CFStringGetCharacters(str, (CFRange){0, additionalLength}, &buf->characters[buf->length]);
    buf->length += additionalLength;
}

// TODO: Should probably make callers pass the length (or at least add a variant where they can)
void OFXMLBufferAppendASCIICString(OFXMLBuffer buf, const char *str)
{
    char c;
    while ((c = *str++)) {
        _OFXMLBufferEnsureSpace(buf, 1);
        buf->characters[buf->length] = c;
        buf->length++;
    }
}

void OFXMLBufferAppendSpaces(OFXMLBuffer buf, CFIndex count)
{
    _OFXMLBufferEnsureSpace(buf, count);
    
    // Can't memset since we are going to a unichar buffer.
    unichar *p = &buf->characters[buf->length];
    
    CFIndex charIndex;
    for (charIndex = 0; charIndex < count; charIndex++)
        p[charIndex] = ' ';
    
    buf->length += count;
}

BOOL OFXMLBufferAppendUTF8Data(OFXMLBuffer buf, CFDataRef data, NSError **outError)
{
    CFStringRef str = CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, data, kCFStringEncodingUTF8);
    if (!str) {
        // Should be very rare if people are being consistent.
        *outError = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OFXMLCannotCreateStringFromUnparsedData userInfo:nil];
        return NO;
    }
    
    OFXMLBufferAppendString(buf, str);
    CFRelease(str);
    return YES;
}

CFDataRef OFXMLBufferCopyData(OFXMLBuffer buf, CFStringEncoding encoding)
{
    CFStringRef str = CFStringCreateWithCharactersNoCopy(kCFAllocatorDefault, buf->characters, buf->length, kCFAllocatorNull/*no free*/);
    OBASSERT(str);
    CFDataRef data = CFStringCreateExternalRepresentation(kCFAllocatorDefault, str, encoding, 0/*lossByte*/);
    CFRelease(str);
    return data;
}
