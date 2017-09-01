// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFString-OFExtensions.h>
#import <Foundation/NSObjCRuntime.h> // for BOOL
#import <OmniFoundation/OFUnicodeUtilities.h>
#import <OmniBase/rcsid.h>
#import <string.h>

RCS_ID("$Id$")


void OFCaseConversionBufferInit(OFCaseConversionBuffer *caseBuffer)
{
    caseBuffer->bufferSize = 128;
    caseBuffer->buffer = CFAllocatorAllocate(kCFAllocatorDefault, caseBuffer->bufferSize * sizeof(*caseBuffer->buffer), 0);
    caseBuffer->string = CFStringCreateMutableWithExternalCharactersNoCopy(kCFAllocatorDefault, caseBuffer->buffer, 0, caseBuffer->bufferSize, kCFAllocatorDefault);
}

void OFCaseConversionBufferDestroy(OFCaseConversionBuffer *caseBuffer)
{
    CFRelease(caseBuffer->string);
    caseBuffer->string = NULL;
    // Don't release the buffer -- the string did that.
    caseBuffer->buffer = NULL;
    caseBuffer->bufferSize = 0;
}


static inline BOOL _OFHasPotentiallyUppercaseCharacter(const UniChar *characters, CFIndex count)
{
    while (count--) {
        UniChar c = *characters++;
        
        if (c > 0x7f)
            return YES;
        if (c >= 'A' && c <= 'Z')
            return YES;
    }
    
    return NO;
}

/*"
Returns a new immutable string that contains the lowercase variant of the given characters.  The buffer of characters provide is left unchanged.
"*/
CFStringRef OFCreateStringByLowercasingCharacters(OFCaseConversionBuffer *caseBuffer, const UniChar *characters, CFIndex count)
{
    // Trivially create a string from the given characters if non of them can possibly be upper case
    if (!_OFHasPotentiallyUppercaseCharacter(characters, count))
        return CFStringCreateWithCharacters(kCFAllocatorDefault, characters, count);

    // Make sure we have enough room to copy the string into our conversion buffer
    if (caseBuffer->bufferSize < count) {
        caseBuffer->bufferSize = count;
        caseBuffer->buffer = CFAllocatorReallocate(kCFAllocatorDefault, caseBuffer->buffer, caseBuffer->bufferSize * sizeof(*caseBuffer->buffer), 0);
    }
    
    // Copy the string into backing store for the conversion string.
    memcpy(caseBuffer->buffer, characters, sizeof(*characters) * count);

    // Reset the external character buffer (and importantly, reset the length of the string in the buffer)
    CFStringSetExternalCharactersNoCopy(caseBuffer->string, caseBuffer->buffer, count, caseBuffer->bufferSize);

    // Lowercase the string, possibly reallocating the external buffer if it needs to grow to accomodate
    // unicode sequences that have different lengths when lowercased.
    CFStringLowercase(caseBuffer->string, NULL);

    // Make sure that if the external buffer had to grow, we don't lose our pointer to it.
    // Sadly, this doesn't let us find the new size, but if it did grow that means that the next time we
    // try to grow it, we'll be less likely to actually get a new pointer from CFAllocatorReallocate().
    caseBuffer->buffer = (UniChar *)CFStringGetCharactersPtr(caseBuffer->string);
    
    // Return a new immutable string.
    return CFStringCreateCopy(kCFAllocatorDefault, caseBuffer->string);
}


/*" Returns a hash code by examining all of the characters in the provided array.  Two strings that differ only in case will return the same hash code. "*/
CFHashCode OFCaseInsensitiveHash(const UniChar *characters, CFIndex length)
{
    CFIndex characterIndex;
    CFHashCode hash;
    UniChar c;
    
    // We will optimistically assume that the string is ASCII
    hash = 0;
    for (characterIndex = 0; characterIndex < length; characterIndex++) {
        c = characters[characterIndex];
        if (c < ' ' || c > '~')
            goto HandleUnicode;
        if (c >= 'A' && c <= 'Z') {
            c = 'a' + (c - 'A');
        }
        
        // Rotate hash by 7 bits (which is relatively prime to 32) and or in the
        // next character at the top of the hash code.
        hash = (c << 16) | ((hash & ((1<<7) - 1)) << (32-7)) | (hash >> 7);
    }
    
    return hash;
    
HandleUnicode:

    // This version is SLOW.  The problem is that we don't know if performing case conversion will require more characters.
    // Fortunately, this should only get called once per value that is put in a hashing container, but it will still get called once per lookup.
    {
        CFMutableStringRef string;
        
        string = CFStringCreateMutable(kCFAllocatorDefault, length);
        CFStringAppendCharacters(string, characters, length);
        CFStringLowercase(string, NULL);
        hash = CFHash(string);
        CFRelease(string);
        
        return hash;
    }
}



Boolean OFCaseInsensitiveStringIsEqual(const void *value1, const void *value2)
{
    OBASSERT([(OB_BRIDGE id)value1 isKindOfClass:[NSString class]] && [(OB_BRIDGE id)value2 isKindOfClass:[NSString class]]);
    return CFStringCompare((CFStringRef)value1, (CFStringRef)value2, kCFCompareCaseInsensitive) == kCFCompareEqualTo;
}

CFHashCode OFCaseInsensitiveStringHash(const void *value)
{
    OBASSERT([(OB_BRIDGE id)value isKindOfClass:[NSString class]]);
    
    // This is the only interesting function in the bunch.  We need to ensure that all
    // case variants of the same string (when 'same' is determine case insensitively)
    // have the same hash code.  We will do this by using CFStringGetCharacters over
    // the first 16 characters of each key.
    // This is obviously not a good hashing algorithm for all strings.
    UniChar characters[16];
    CFIndex length;
    CFStringRef string;
    
    string = (CFStringRef)value;
    
    length = CFStringGetLength(string);
    if (length > 16)
        length = 16;
    
    CFStringGetCharacters(string, CFRangeMake(0, length), characters);
    
    return OFCaseInsensitiveHash(characters, length);
}

CFIndex OFAppendStringBytesToBuffer(CFMutableDataRef buffer, CFStringRef source, CFRange range, CFStringEncoding encoding, UInt8 lossByte, Boolean isExternalRepresentation)
{
    CFIndex bufSize = CFStringGetMaximumSizeForEncoding(range.length, encoding);
    CFIndex origLength = CFDataGetLength(buffer);
    CFIndex convertedChars, convertedBytes;

    CFDataSetLength(buffer, origLength + bufSize);
    convertedBytes = 0;
    convertedChars = CFStringGetBytes(source, range,
                                      encoding, lossByte, isExternalRepresentation,
                                      CFDataGetMutableBytePtr(buffer) + origLength,
                                      bufSize, &convertedBytes);
    CFDataSetLength(buffer, origLength + convertedBytes);

    return convertedChars;
}

CFHashCode OFStringHash_djb2(CFStringRef string)
{
    /*
     From <http://www.cs.yorku.ca/~oz/hash.html>

     djb2
     this algorithm (k=33) was first reported by dan bernstein many years ago in comp.lang.c. another version of this algorithm (now favored by bernstein) uses xor: hash(i) = hash(i - 1) * 33 ^ str[i]; the magic of number 33 (why it works better than many other constants, prime or not) has never been adequately explained.
     
     Dan Bernstein's explanation of the initial value 5381:
        Message-ID <29997.Jun2503.57.3491@kramden.acf.nyu.edu> 24 Jun 1991
     
     Chris Torek attributes the algorithm originally to Gosling Emacs:
        Message-ID <bbjotv$bf0$1@elf.eng.bsdi.com> 3 Jun 2003
     
     The related Fowler-Noll-Vo hash:
        http://www.isthe.com/chongo/tech/comp/fnv/
    */
#define HASH_INIT CFHashCode hash = 5381
#define HASH_UPDATE(value) hash = ((hash << 5) + hash) + (value) /* hash * 33 + character */

    HASH_INIT;

    CFStringInlineBuffer buffer;
    CFIndex stringLength = CFStringGetLength(string);
    CFStringInitInlineBuffer(string, &buffer, CFRangeMake(0, stringLength));

    for (CFIndex stringIndex = 0; stringIndex < stringLength; stringIndex++) {
        UniChar character = CFStringGetCharacterFromInlineBuffer(&buffer, stringIndex);
        HASH_UPDATE(character);
    }

    return hash;
}

CFHashCode OFCharactersHash_djb2(const UniChar *characters, NSUInteger characterCount)
{
    HASH_INIT;

    for (NSUInteger characterIndex = 0; characterIndex < characterCount; characterIndex++) {
        UniChar character = characters[characterIndex];
        HASH_UPDATE(character);
    }

    return hash;
}

CFHashCode OFBytesHash_djb2(const void *bytes, NSUInteger byteCount)
{
    HASH_INIT;

    NSUInteger byteIndex = 0;
    while (byteIndex < byteCount) {
        // We could probably load multiple bytes out of the pointer at a time, which might be worth it for performance (but we'd need more code for handling various sizes modulo the word size we used).
        NSUInteger byte = ((const unsigned char *)bytes)[byteIndex];
        byteIndex++;

        HASH_UPDATE(byte);
    }
    return hash;
}


BOOL OFStringContainsInvalidSequences(CFStringRef str)
{
    const CFIndex stringLength = CFStringGetLength(str);
    CFStringInlineBuffer buf;
    
    /* Almost everything we call in this function is a simple inline, so this should be reasonably fast */
    
    CFStringInitInlineBuffer(str, &buf, (CFRange){ .location = 0, .length = stringLength });
    for(CFIndex strIndex = 0; strIndex < stringLength; strIndex ++) {
        /* CFStrings are a sequence of UTF-16 words. Most of these map directly to Unicode code points, except for the surrogate pair range. */
        
        UniChar ch = CFStringGetCharacterFromInlineBuffer(&buf, strIndex);
        switch(OFCharacterIsSurrogate(ch)) {
            case OFIsSurrogate_No:
                /* Common case: Not a surrogate pair, but a Basic-Multilingual-Plane character. */
                /* Check for a handful of invalid code points. */
                if (ch == 0xFFFE || ch == 0xFFFF || (ch >= 0xFDD0 && ch < 0xFDF0))
                    return YES;
                break;
            case OFIsSurrogate_HighSurrogate:
            {
                /* A high surrogate must be immediately followed by a low surrogate */
                
                /* CFStringGetCharacterFromInlineBuffer() will safely return 0 if strIndex+1 is out of range */
                UniChar nextCh = CFStringGetCharacterFromInlineBuffer(&buf, strIndex+1);
                if (OFCharacterIsSurrogate(nextCh) != OFIsSurrogate_LowSurrogate)
                    return YES;
                
                UnicodeScalarValue longch = OFCharacterFromSurrogatePair(ch, nextCh);
                if ((longch & 0xFFFE) == 0xFFFE)
                    return YES;  // All code points eding in FFFE or FFFF are invalid, for some reason (possibly to make BOMs work?)
                
                // Skip past the low surrogate we've already checked
                strIndex ++;
                break;
            }
            default:
            case OFIsSurrogate_LowSurrogate:
                /* If we run into a low surrogate half not preceded by a high surrogate, or if OFCharacterIsSurrogate() somehow returns something unexpected, then fail. */
                return YES;
        }
    }
    
    /* Nothing invalid here! */
    return NO;
}

CFRange OFStringRangeOfNextInvalidCodepoint(CFStringRef str, CFRange searchRange, CFCharacterSetRef additionalInvalides)
{
    CFStringInlineBuffer buf;
    
    /* Almost everything we call in this function is a simple inline, so this should be reasonably fast */
    
    CFStringInitInlineBuffer(str, &buf, searchRange);
    for(CFIndex strIndex = 0; strIndex < searchRange.length; strIndex ++) {
        /* CFStrings are a sequence of UTF-16 words. Most of these map directly to Unicode code points, except for the surrogate pair range. */
        
        UniChar ch = CFStringGetCharacterFromInlineBuffer(&buf, strIndex);
        if (__builtin_expect((ch & 0xF800) == 0xD800, 0)) {
            if ((ch & 0x0400) == 0) {
                /* A high surrogate must be immediately followed by a low surrogate */
                
                /* CFStringGetCharacterFromInlineBuffer() will safely return 0 if strIndex+1 is out of range */
                UniChar nextCh = CFStringGetCharacterFromInlineBuffer(&buf, strIndex+1);
                if (!CFStringIsSurrogateLowCharacter(nextCh))
                    return (CFRange){ .location = strIndex + searchRange.location, .length = 1 };
                
                UnicodeScalarValue longch = OFCharacterFromSurrogatePair(ch, nextCh);
                if ((longch & 0xFFFE) == 0xFFFE) {
                    // All code points eding in FFFE or FFFF are invalid, for some reason (possibly to make BOMs work?)
                    return (CFRange){ .location = strIndex + searchRange.location, .length = 2 };
                }
                
                if (additionalInvalides && CFCharacterSetIsLongCharacterMember(additionalInvalides, longch)) {
                    return (CFRange){ .location = strIndex + searchRange.location, .length = 2 };
                }
                
                // Skip past the low surrogate we've already checked
                strIndex ++;
            } else {
                /* If we run into a low surrogate half not preceded by a high surrogate, then fail. */
                return (CFRange){ .location = strIndex + searchRange.location, .length = 1 };
            }
        } else {
            /* The common case: not a surrogate. */
            /* Common case: Not a surrogate pair, but a Basic-Multilingual-Plane character. */
            /* Check for a handful of invalid code points. */
            if (ch == 0xFFFE || ch == 0xFFFF || (ch >= 0xFDD0 && ch < 0xFDF0))
                return (CFRange){ .location = strIndex + searchRange.location, .length = 1 };
            if (additionalInvalides && CFCharacterSetIsCharacterMember(additionalInvalides, ch))
                return (CFRange){ .location = strIndex + searchRange.location, .length = 1 };
        }
    }
    
    /* Nothing invalid here! */
    return (CFRange){ .location = kCFNotFound, .length = 0 };
}



