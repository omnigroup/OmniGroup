// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSString-OFSimpleMatching.h>

#import <OmniFoundation/NSString-OFCharacterEnumeration.h>
#import <OmniFoundation/OFCharacterSet.h>

RCS_ID("$Id$");

@implementation NSString (OFSimpleMatching)

+ (BOOL)isEmptyString:(NSString *)string;
// Returns YES if the string is nil or equal to @""
{
    // Note that [string length] == 0 can be false when [string isEqualToString:@""] is true, because these are Unicode strings.
    return string == nil || [string isEqualToString:@""];
}

- (BOOL)containsCharacterInOFCharacterSet:(OFCharacterSet *)searchSet;
{
    OFStringStartLoopThroughCharacters(self, character) {
        if (OFCharacterSetHasMember(searchSet, character))
            return YES;
    } OFStringEndLoopThroughCharacters;
    
    return NO;
}

- (BOOL)containsCharacterInSet:(NSCharacterSet *)searchSet;
{
    NSRange characterRange = [self rangeOfCharacterFromSet:searchSet];
    return characterRange.length != 0;
}

- (BOOL)containsString:(NSString *)searchString options:(unsigned int)mask;
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

#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
- (BOOL)isEqualToCString:(const char *)cString;
{
    if (!cString)
	return NO;
    return [self isEqualToString:[NSString stringWithCString:cString]];
}
#endif

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
    NSUInteger firstBad;
    CFIndex thisBad;
    CFIndex charactersConverted;
    NSRange testNSRange;
    CFRange testCFRange;
    CFIndex bufLen = 1024;
    CFIndex usedBufLen;
    int myLength; 
    
    myLength = [self length];
    firstBad = [self indexOfCharacterNotRepresentableInCFEncoding:anEncoding];
    if (firstBad == NSNotFound)
        return NSMakeRange(myLength, 0);
    
    for (thisBad = firstBad; thisBad < myLength; thisBad += testCFRange.length) {
        
        // there's no CoreFoundation function for this, sigh
        testNSRange = [self rangeOfComposedCharacterSequenceAtIndex:thisBad];
        if (testNSRange.length == 0) {
            // We've reached the end of the string buffer
            break;
        }
        
        testCFRange.location = thisBad;
        testCFRange.length = testNSRange.length;
        
        usedBufLen = 0;
        charactersConverted = CFStringGetBytes((CFStringRef)self, testCFRange, anEncoding, 0, FALSE, NULL, bufLen, &usedBufLen);
        if (charactersConverted > 0)
            break;
    };
    
    return NSMakeRange(firstBad, thisBad - firstBad);
}

@end
