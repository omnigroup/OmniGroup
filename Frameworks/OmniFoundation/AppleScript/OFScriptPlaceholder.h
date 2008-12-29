// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

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
