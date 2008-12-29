// Copyright 2002-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSAppleScript.h>

@class NSAppleEventDescriptor, NSArray, NSData;
@class NSAttributedString;

@interface NSAppleScript (OAExtensions)

- (id)initWithData:(NSData *)data error:(NSDictionary **)errorInfo;
- (NSData *)compiledData;

+ (NSAttributedString *)attributedStringFromScriptResult:(NSAppleEventDescriptor *)descriptor;

// Reads AppleScript's source formatting settings; styleNumber should be one of the constants from AppleScript.h.
+ (NSDictionary *)stringAttributesForAppleScriptStyle:(int)styleNumber;
    // Only includes attributes applicable to the underlying AppleScript implementation (NSFontAttributeName, NSForegroundColorAttributeName, and NSUnderlineStyleAttributeName).

@end

