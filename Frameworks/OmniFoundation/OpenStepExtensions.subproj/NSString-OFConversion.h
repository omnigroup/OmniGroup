// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSString-OFConversion.h 104167 2008-08-19 22:50:52Z wiml $

#import <Foundation/NSString.h>

#import <Foundation/NSDecimal.h>

@class NSData, NSDecimalNumber;

@interface NSString (OFConversion)

+ (NSString *)stringWithData:(NSData *)data encoding:(NSStringEncoding)encoding;

- (BOOL)boolValue;
- (long long int)longLongValue;
- (unsigned long long int)unsignedLongLongValue;
- (unsigned int)unsignedIntValue;
- (intmax_t)maxIntegerValue;
- (uintmax_t)maxUnsignedIntegerValue;
- (NSDecimal)decimalValue;
- (NSDecimalNumber *)decimalNumberValue;
- (NSNumber *)numberValue;
- (NSArray *)arrayValue;
- (NSDictionary *)dictionaryValue;
- (NSData *)dataValue;

- (unsigned int)hexValue;

/* Covers for the C functions in CoreFoundation */
- (NSData *)dataUsingCFEncoding:(CFStringEncoding)anEncoding;
- (NSData *)dataUsingCFEncoding:(CFStringEncoding)anEncoding allowLossyConversion:(BOOL)lossy;

@end
