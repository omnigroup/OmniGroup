// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIButton.h>

@interface OUIAttentionSeekingButton : UIButton

@property (nonatomic, getter=isSeekingAttention) BOOL seekingAttention;

- (instancetype)initForAttentionKey:(NSString *)key normalImage:(UIImage *)normalImage attentionSeekingImage:(UIImage *)attentionSeekingImage dotOrigin:(CGPoint)dotOrigin;

@end

