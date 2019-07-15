// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@protocol OUILoupeOverlaySubject <NSObject>
@optional

// These will only be sent to non-opaque subject views. If -drawLoupeOverlayBackgroundInRect: it will be used in preference to -loupeOverlayBackgroundColor. If neither is implemented, white will be used.

- (void)drawLoupeOverlayBackgroundInRect:(CGRect)rect; // In the subject view's coordinate system
- (UIColor *)loupeOverlayBackgroundColor;

// If drawScaledContentForLoupe: is not implemented, the drawScaledContent: will be called

- (void)drawScaledContentForLoupe:(CGRect)rect;

@end
