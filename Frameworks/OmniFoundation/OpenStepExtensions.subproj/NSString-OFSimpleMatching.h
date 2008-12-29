// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSString-OFSimpleMatching.h 102902 2008-07-15 22:13:08Z wiml $

#import <Foundation/NSString.h>

#import <CoreFoundation/CFString.h>

@class OFCharacterSet;

@interface NSString (OFSimpleMatching)

+ (BOOL)isEmptyString:(NSString *)string;
// Returns YES if the string is nil or equal to @""

- (BOOL)containsCharacterInOFCharacterSet:(OFCharacterSet *)searchSet;
- (BOOL)containsCharacterInSet:(NSCharacterSet *)searchSet;
- (BOOL)containsString:(NSString *)searchString options:(unsigned int)mask;
- (BOOL)containsString:(NSString *)searchString;
- (BOOL)hasLeadingWhitespace;
#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
- (BOOL)isEqualToCString:(const char *)cString;
#endif

- (NSUInteger)indexOfCharacterNotRepresentableInCFEncoding:(CFStringEncoding)anEncoding;
- (NSUInteger)indexOfCharacterNotRepresentableInCFEncoding:(CFStringEncoding)anEncoding range:(NSRange)aRange;
- (NSRange)rangeOfCharactersNotRepresentableInCFEncoding:(CFStringEncoding)anEncoding;

@end
