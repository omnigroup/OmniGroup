// Copyright 2003-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFScriptPlaceholder.h>
#import <Foundation/NSScriptClassDescription.h>

RCS_ID("$Id$");

@implementation OFScriptPlaceholder

- initWithTargetClass:(Class)targetClass;
{
    OBPRECONDITION(targetClass);
    OBPRECONDITION([[NSClassDescription classDescriptionForClass:targetClass] isKindOfClass:[NSScriptClassDescription class]]);
    _targetClass = targetClass;
    return self;
}

- (void)dealloc;
{
    [_target release];
    [_scriptingProperties release];
    [super dealloc];
}

- (Class)targetClass;
{
    return _targetClass;
}

- (void)setTarget:(id)target;
{
    OBPRECONDITION(!_target);  // should really only set this once
    OBPRECONDITION([target isKindOfClass:_targetClass]);
    
    [_target release];
    _target = [target retain];
}

- (id)target;
{
    return _target;
}

- (NSScriptObjectSpecifier *)objectSpecifier;
{
    OBPRECONDITION(_target);
    return [_target objectSpecifier];
}

- (NSDictionary *)scriptingProperties;
{
    return _scriptingProperties;
}

- (void)setScriptingProperties:(NSDictionary *)properties;
{
    [_scriptingProperties release];
    _scriptingProperties = [[NSDictionary alloc] initWithDictionary:properties];
}

//
// Debugging
//
- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setValue:_targetClass forKey:@"_targetClass"];
    [dict setValue:_target forKey:@"_target"];
    [dict setValue:_scriptingProperties forKey:@"_scriptingProperties"];
    return dict;
}

@end
