// Copyright 2009-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <QuartzCore/CAAnimation.h>

@class NSResponder, NSView;

@interface OQFlipSwapViewAnimation : CABasicAnimation

+ (void)replaceView:(NSView *)oldView withView:(NSView *)newView setFirstResponder:(NSResponder *)newFirstResponder;

@end
