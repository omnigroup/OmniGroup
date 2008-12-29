// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/AppleScript/OFScriptPlaceholder.h 68913 2005-10-03 19:36:19Z kc $

#import <Foundation/NSObject.h>

@class NSDictionary, NSScriptClassDescription, NSScriptObjectSpecifier;

@interface OFScriptPlaceholder : NSObject
{
    Class _targetClass;
    id _target;
    NSDictionary *_scriptingProperties;
}

- initWithTargetClass:(Class)targetClass;

- (Class)targetClass;

- (void)setTarget:(id)target;
- (id)target;

- (NSScriptObjectSpecifier *)objectSpecifier;

- (NSDictionary *)scriptingProperties;
- (void)setScriptingProperties:(NSDictionary *)properties;

@end
