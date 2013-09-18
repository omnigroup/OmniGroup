// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class UIImage;

@interface OUILoadedImage : NSObject
@property(nonatomic,strong) UIImage *image;
@property(nonatomic) CGSize size;
@end

extern OUILoadedImage *OUILoadImage(NSString *name);



