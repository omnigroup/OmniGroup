// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@protocol OUIDocumentPreview <NSObject>
@property(readonly,getter=isScalable) BOOL scalable;
- (BOOL)isValidAtSize:(CGSize)targetSize;
- (CGAffineTransform)transformForTargetRect:(CGRect)targetRect;
@property(readonly) CGRect untransformedPageRect;
@property(retain) UIImage *cachedImage;
@end
