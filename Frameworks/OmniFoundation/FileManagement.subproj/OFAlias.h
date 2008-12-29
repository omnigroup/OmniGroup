// Copyright 2004-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/FileManagement.subproj/OFAlias.h 98221 2008-03-04 21:06:19Z kc $

#import <Foundation/NSObject.h>
#import <Carbon/Carbon.h>

@class NSData; 	// Foundation

@interface OFAlias : NSObject 
{
    AliasHandle _aliasHandle;
}

// API
- initWithPath:(NSString *)path;
- initWithData:(NSData *)data;

// returns nil if the alias doesn't resolve
- (NSString *)path;
- (NSString *)pathAllowingUnresolvedPath;
- (NSString *)pathAllowingUserInterface:(BOOL)allowUserInterface missingVolume:(BOOL *)missingVolume;
- (NSString *)pathAllowingUserInterface:(BOOL)allowUserInterface missingVolume:(BOOL *)missingVolume allowUnresolvedPath:(BOOL)allowUnresolvedPath;
- (NSData *)data;

@end
