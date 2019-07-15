// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSString.h>

#import <CoreFoundation/CFString.h>

@class OFCharacterSet;

@interface NSString (OFSimpleMatching)

+ (BOOL)isEmptyString:(NSString *)string;
// Returns YES if the string is nil or equal to @""

- (BOOL)containsCharacterInOFCharacterSet:(OFCharacterSet *)searchSet;
- (BOOL)containsCharacterInSet:(NSCharacterSet *)searchSet;
- (BOOL)containsString:(NSString *)searchString options:(NSStringCompareOptions)mask;
- (BOOL)containsString:(NSString *)searchString;
- (BOOL)hasLeadingWhitespace;

- (NSUInteger)indexOfCharacterNotRepresentableInCFEncoding:(CFStringEncoding)anEncoding;
- (NSUInteger)indexOfCharacterNotRepresentableInCFEncoding:(CFStringEncoding)anEncoding range:(NSRange)aRange;
- (NSRange)rangeOfCharactersNotRepresentableInCFEncoding:(CFStringEncoding)anEncoding;

@end

// clang doesn't understand that +isEmptyString: is returns YES for nils, and so nullabilty warnings are emitted for cases where they shouldn't.
static inline BOOL OFIsEmptyString(NSString *string) {
    // Note that [string length] == 0 can be false when [string isEqualToString:@""] is true, because these are Unicode strings.
    return string == nil || [string isEqualToString:@""];
}
