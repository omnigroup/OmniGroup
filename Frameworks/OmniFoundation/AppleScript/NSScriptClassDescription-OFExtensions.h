// Copyright 2006-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/AppleScript/NSScriptClassDescription-OFExtensions.h 93494 2007-10-26 18:43:00Z kc $

#import <Foundation/NSScriptClassDescription.h>

@interface NSScriptClassDescription (OFExtensions)
+ (NSScriptClassDescription *)commonScriptClassDescriptionForObjects:(NSArray *)objects;
- (BOOL)isKindOfScriptClassDescription:(NSScriptClassDescription *)desc;
@end
