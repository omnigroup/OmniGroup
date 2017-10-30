// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIResponder-OUIExtensions.h>

#import <OmniUI/UIApplication-OUIExtensions.h>

RCS_ID("$Id$")

@implementation UIResponder (OUIExtensions)

static UIResponder * _Nullable _firstResponder = nil;

+ (nullable UIResponder *)firstResponder;
{
    // Adapted from http://stackoverflow.com/a/14135456/322427
    // The trick is that sending the action to nil sends it to the first responder.
    
    _firstResponder = nil;
    
    // This isn't marked as unavailable from extensions because it has a cascading effect on MultiPaneController, and it isn't transitive in Swift anyway.
    // https://bugs.swift.org/browse/SR-1226
    //
    // Bypass compiler checks by using dynamic code.
    id application = [NSClassFromString(@"UIApplication") sharedApplication];
    [application sendAction:@selector(omni_findFirstResponder:) to:nil from:nil forEvent:nil];
    
    id result = _firstResponder;
    
    OBRetainAutorelease(result);
    _firstResponder = nil;
    
    return result;
}

- (void)omni_findFirstResponder:(id)sender;
{
    _firstResponder = self;
}

- (BOOL)isInActiveResponderChainPrecedingResponder:(UIResponder *)responder;
{
    // TODO: Should we try to detect responder chain loops and exist early to prevent infinite loops?
    
    UIResponder *nextResponder = UIResponder.firstResponder;
    BOOL hasSeenSelf = NO;
    
    while (nextResponder != nil) {
        if (nextResponder == self) {
            hasSeenSelf = YES;
        }
        
        if (nextResponder == responder) {
            return hasSeenSelf;
        }
        
        nextResponder = nextResponder.nextResponder;
    }
    
    return NO;
}

@end
