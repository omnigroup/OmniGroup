// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSString-OFSimpleMatching.h>

#import <OmniFoundation/OFCharacterSet.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

RCS_ID("$Id$");

@implementation NSString (OFSimpleMatching)

+ (BOOL)isEmptyString:(NSString *)string;
// Returns YES if the string is nil or equal to @""
{
    return OFIsEmptyString(string);
}

- (BOOL)containsCharacterInOFCharacterSet:(OFCharacterSet *)searchSet;
{
    CFStringInlineBuffer charBuf;
    CFIndex charCount = (CFIndex)[self length];
    CFStringInitInlineBuffer((CFStringRef)self, &charBuf, (CFRange){0, charCount});
    for(CFIndex charIndex = 0; charIndex < charCount; charIndex ++) {
        if (OFCharacterSetHasMember(searchSet, CFStringGetCharacterFromInlineBuffer(&charBuf, charIndex)))
            return YES;
    }
    
    return NO;
}

- (BOOL)containsCharacterInSet:(NSCharacterSet *)searchSet;
{
    NSRange characterRange = [self rangeOfCharacterFromSet:searchSet];
    return characterRange.length != 0;
}

- (BOOL)containsString:(NSString *)searchString options:(NSStringCompareOptions)mask;
{
    return !searchString || [searchString length] == 0 || [self rangeOfString:searchString options:mask].length > 0;
}

- (BOOL)containsString:(NSString *)searchString;
{
    return !searchString || [searchString length] == 0 || [self rangeOfString:searchString].length > 0;
}

- (BOOL)hasLeadingWhitespace;
{
    if ([self length] == 0)
	return NO;
    switch ([self characterAtIndex:0]) {
        case ' ':
        case '\t':
        case '\r':
        case '\n':
            return YES;
        default:
            return NO;
    }
}

- (NSUInteger)indexOfCharacterNotRepresentableInCFEncoding:(CFStringEncoding)anEncoding;
{
    return [self indexOfCharacterNotRepresentableInCFEncoding:anEncoding range:NSMakeRange(0, [self length])];
}

- (NSUInteger)indexOfCharacterNotRepresentableInCFEncoding:(CFStringEncoding)anEncoding range:(NSRange)aRange;
{
    CFIndex usedBufLen;
    CFIndex thisBufferCharacters;
    CFRange scanningRange;
    CFIndex bufLen = 1024;  // warning: this routine will fail if any single character requires more than 1024 bytes to represent! (ha, ha)
    
    scanningRange.location = aRange.location;
    scanningRange.length = aRange.length;
    while (1) {
        if (!(scanningRange.length))
            return NSNotFound;
        
        usedBufLen = 0;
        thisBufferCharacters = CFStringGetBytes((CFStringRef)self, scanningRange, anEncoding, 0, FALSE, NULL, bufLen, &usedBufLen);
        if (thisBufferCharacters == 0)
            break;
        OBASSERT(thisBufferCharacters <= scanningRange.length);
        scanningRange.location += thisBufferCharacters;
        scanningRange.length -= thisBufferCharacters;
    }
    
    return scanningRange.location;
}

- (NSRange)rangeOfCharactersNotRepresentableInCFEncoding:(CFStringEncoding)anEncoding
{    
    NSUInteger myLength = [self length];
    NSUInteger firstBad = [self indexOfCharacterNotRepresentableInCFEncoding:anEncoding];
    if (firstBad == NSNotFound)
        return NSMakeRange(myLength, 0);
    
    CFRange testCFRange;
    NSUInteger thisBad;
    for (thisBad = firstBad; thisBad < myLength; thisBad += testCFRange.length) {
        
        // there's no CoreFoundation function for this, sigh
        NSRange testNSRange = [self rangeOfComposedCharacterSequenceAtIndex:thisBad];
        if (testNSRange.length == 0) {
            // We've reached the end of the string buffer
            break;
        }
        
        testCFRange = CFRangeMake(thisBad, testNSRange.length);
        CFIndex usedBufLen = 0;
        CFIndex charactersConverted = CFStringGetBytes((CFStringRef)self, testCFRange, anEncoding, 0, FALSE, NULL/*buffer*/, 0/*maxBufLen*/, &usedBufLen);
        if (charactersConverted > 0)
            break;
    };
    
    return NSMakeRange(firstBad, thisBad - firstBad);
}

@end
