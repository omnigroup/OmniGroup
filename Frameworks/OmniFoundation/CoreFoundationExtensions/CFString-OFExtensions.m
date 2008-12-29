// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFString-OFExtensions.h>
#import <Foundation/NSObjCRuntime.h> // for BOOL
#import <NSString-OFCharacterEnumeration.h> // for OFStringStartLoopThroughCharacters/OFStringEndLoopThroughCharacters
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
    OBASSERT([(id)value1 isKindOfClass:[NSString class]] && [(id)value2 isKindOfClass:[NSString class]]);
    return CFStringCompare((CFStringRef)value1, (CFStringRef)value2, kCFCompareCaseInsensitive) == kCFCompareEqualTo;
}

CFHashCode OFCaseInsensitiveStringHash(const void *value)
{
    OBASSERT([(id)value isKindOfClass:[NSString class]]);
    
    // This is the only interesting function in the bunch.  We need to ensure that all
    // case variants of the same string (when 'same' is determine case insensitively)
    // have the same hash code.  We will do this by using CFStringGetCharacters over
    // the first 16 characters of each key.
    // This is obviously not a good hashing algorithm for all strings.
    UniChar characters[16];
    NSUInteger length;
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

unsigned long OFStringHash_djb2(CFStringRef string)
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
    unsigned long hash = 5381;
    const UniChar *characterPointer;

    characterPointer = CFStringGetCharactersPtr(string);
    if (characterPointer) {
        /* If the string already has a unichar-based representation, use it */
        CFIndex count = CFStringGetLength(string);
        while(count --) {
            UniChar character = *characterPointer++;
            hash = ((hash << 5) + hash) + character; /* hash * 33 + character */
        }
    } else {
        /* Otherwise, use a character buffer */
        OFStringStartLoopThroughCharacters((NSString *)string, character) {
            hash = ((hash << 5) + hash) + character; /* hash * 33 + character */
        } OFStringEndLoopThroughCharacters;
    }
    
    return hash;
}

