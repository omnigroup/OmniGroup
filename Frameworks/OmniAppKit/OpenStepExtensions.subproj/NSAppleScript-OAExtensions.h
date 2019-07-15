// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSAppleScript.h>

@class NSAppleEventDescriptor, NSArray, NSData;
@class NSAttributedString;

@interface NSAppleScript (OAExtensions)

- (id)initWithData:(NSData *)data error:(NSDictionary **)errorInfo;
- (NSData *)compiledData;

@end

