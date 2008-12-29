// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/branches/Staff/bungi/OmniFocus-20080310-iPhoneFactor/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSString-OFConversion.h 98499 2008-03-11 03:23:38Z bungi $

#import <Foundation/NSString.h>

@interface NSString (OFURLEncoding)

/* URL encoding */
+ (void)setURLEncoding:(CFStringEncoding)newURLEncoding;
+ (CFStringEncoding)urlEncoding;

+ (NSString *)decodeURLString:(NSString *)encodedString encoding:(CFStringEncoding)thisUrlEncoding;
+ (NSString *)decodeURLString:(NSString *)encodedString;

- (NSData *)dataUsingCFEncoding:(CFStringEncoding)anEncoding allowLossyConversion:(BOOL)lossy hexEscapes:(NSString *)escapePrefix;

+ (NSString *)encodeURLString:(NSString *)unencodedString asQuery:(BOOL)asQuery leaveSlashes:(BOOL)leaveSlashes leaveColons:(BOOL)leaveColons;
+ (NSString *)encodeURLString:(NSString *)unencodedString encoding:(CFStringEncoding)thisUrlEncoding asQuery:(BOOL)asQuery leaveSlashes:(BOOL)leaveSlashes leaveColons:(BOOL)leaveColons;
- (NSString *)fullyEncodeAsIURI;  // This takes a string which is already in %-escaped URI format and fully escapes any characters which are not safe. Slashes, question marks, etc. are unaffected.
- (NSString *)fullyEncodeAsIURIReference;  // Same as -fullyEncodeAsIURI except that number signs are allowed (see RFC2396 section 4).

@end
