// Copyright 2005-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQTargetAnimation.h>

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation OQTargetAnimation

// Selector should have the same signautre as -setCurrentProgress:
- initWithTarget:(id)target selector:(SEL)selector;
{
    if (!(self = [super init]))
        return nil;
    
    _target = [target retain];
    _selector = selector;
    
    // -performSelector: requires id argument.  Our target/selector must have the signature:
    // - (void)setProgress:(NSAnimationProgress)progress forAnimation:(OQTargetAnimation *)animation userInfo:(void *)userInfo;
    // We can't use objc_msgSend since it will promote floats to doubles in the varargs.
    
    // TODO: Validate that the signature of this method is correct and raise
    _imp = (typeof(_imp))[target methodForSelector:_selector];
    OBASSERT(_imp);
    
    return self;
}

- (void)dealloc;
{
    [_target release];
    [super dealloc];
}

- (void)setUserInfo:(void *)userInfo;
{
    _userInfo = userInfo;
}

- (void *)userInfo;
{
    return _userInfo;
}

- (void)setCurrentProgress:(NSAnimationProgress)progress;
{
    [super setCurrentProgress:progress];
    _imp(_target, _selector, progress, self, _userInfo);
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    // If this is ever called, we need to figure out what to do with userInfo, it being a void *.
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

@end
