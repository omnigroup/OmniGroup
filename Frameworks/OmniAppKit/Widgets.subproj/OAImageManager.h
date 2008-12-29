// Copyright 2003-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAImageManager.h 93428 2007-10-25 16:36:11Z kc $

#import <Foundation/NSObject.h>

@class NSBundle, NSMutableDictionary, NSString;
@class NSImage;

@interface OAImageManager : NSObject
{
    NSMutableDictionary *nonexistentImageNames;
}

// API
+ (OAImageManager *)sharedImageManager;
+ (void)setSharedImageManager:(OAImageManager *)newInstance;

- (NSImage *)imageNamed:(NSString *)imageName;
- (NSImage *)imageNamed:(NSString *)imageName inBundle:(NSBundle *)aBundle;

@end
