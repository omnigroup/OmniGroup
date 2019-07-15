// Copyright 2004-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class NSData; 	// Foundation

@interface OFAlias : NSObject 
{
@private
    NSData *_aliasData;
}

// API

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- initWithPath:(NSString *)path;
#endif

- initWithData:(NSData *)data;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
// returns nil if the alias doesn't resolve
- (NSString *)path;
- (NSString *)pathAllowingUnresolvedPath;
- (NSString *)pathAllowingUserInterface:(BOOL)allowUserInterface missingVolume:(BOOL *)missingVolume;
- (NSString *)pathAllowingUserInterface:(BOOL)allowUserInterface missingVolume:(BOOL *)missingVolume allowUnresolvedPath:(BOOL)allowUnresolvedPath;
#endif

@property(readonly,nonatomic) NSData *data;

@end
