// Copyright 2005-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <QuartzCore/CIContext.h>

@interface CIContext (OQExtensions)
- (void)fillRect:(CGRect)rect withColor:(CIColor *)color;
- (BOOL)writePNGImage:(CIImage *)image fromRect:(CGRect)rect toURL:(NSURL *)url;
@end
