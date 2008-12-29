// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OASpringLoadHelper.h 66043 2005-07-25 21:17:05Z kc $

#import <Foundation/NSObject.h>

@class NSTimer;
@class OASpringLoadHelper;

#import <AppKit/NSNibDeclarations.h>
#import <Foundation/NSGeometry.h> // For NSRect

@protocol OASpringLoadHelper

- (BOOL)springLoadHelperShouldFlash:(OASpringLoadHelper *)aHelper;
// Return YES if the spring load should send -springLoadHelper:wantsFlash: a few times before triggering the spring load (via -springLoadHelperWantsSpringLoad:)

- (void)springLoadHelper:(OASpringLoadHelper *)aHelper wantsFlash:(BOOL)shouldFlash;
// Only fired if -springLoadHelperShouldFlash: returns YES.  If shouldFlash is YES, the receiver should draw itself in its highlighted state.  If NO, the highlight should be cleared.

- (void)springLoadHelperWantsSpringLoad:(OASpringLoadHelper *)aHelper;
    // Notifies the receiver that it should trigger its "spring load" behavior.

@end

@interface OASpringLoadHelper : NSObject
{
    id <OASpringLoadHelper> nonretainedDelegate;
    NSTimer *springTimer;
    unsigned int flashCount;
    NSRect slopRect;
}

+ (OASpringLoadHelper *)springLoadHelperWithDelegate:(id <OASpringLoadHelper>)aDelegate;

- (void)beginSpringLoad;
- (void)updateSpringLoad;
- (void)cancelSpringLoad;

@end
