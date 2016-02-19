// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAttentionSeekingButton.h>

RCS_ID("$Id$")

#import <OmniUI/OUIAppController.h> // for OUIAttentionSeekingNotification
#import <OmniAppKit/OAAppearanceColors.h>

@interface OUIAttentionSeekingButton ()

@property (nonatomic, copy) NSString *attentionKey;

@property (nonatomic, strong) UIImage *normalImage;
@property (nonatomic, strong) UIImage *attentionSeekingImage;

@property (nonatomic, strong) UIImageView *attentionDot;

@end

@implementation OUIAttentionSeekingButton

- (instancetype)init{
    OBRejectUnusedImplementation(self, _cmd);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (instancetype)initWithFrame:(CGRect)frame
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (instancetype)initForAttentionKey:(NSString *)key normalImage:(UIImage *)normalImage attentionSeekingImage:(UIImage *)attentionSeekingImage dotOrigin:(CGPoint)dotOrigin;
{
    if (self = [super initWithFrame:CGRectMake(0, 0, normalImage.size.width, normalImage.size.height)]) {
        _attentionKey = key;
        
        _normalImage = normalImage;
        _attentionSeekingImage = attentionSeekingImage;
        
        [self setImage:normalImage forState:UIControlStateNormal];
        
        _attentionDot = [self createAttentionDot];
        [self addSubview:_attentionDot];
        _attentionDot.translatesAutoresizingMaskIntoConstraints = NO;
        NSLayoutConstraint *topConstraint = [_attentionDot.topAnchor constraintEqualToAnchor:self.imageView.topAnchor];
        topConstraint.constant = dotOrigin.y;
        NSLayoutConstraint *leftConstraint = [_attentionDot.leftAnchor constraintEqualToAnchor:self.imageView.leftAnchor];
        leftConstraint.constant = dotOrigin.x;
        NSArray *constraints = @[ topConstraint, leftConstraint ];
        [NSLayoutConstraint activateConstraints:constraints];
        
        _attentionDot.hidden = YES;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(attentionSeekingNeedDidChange:) name:OUIAttentionSeekingNotification object:nil];
        
        return self;

    } else {
        return nil;
    }
}

- (UIImageView *)createAttentionDot
{
    UIImage *attentionDotTemplate = [[UIImage imageNamed:@"OUIAttentionDot" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImageView *dot = [[UIImageView alloc] initWithImage:attentionDotTemplate];
    dot.tintColor = [[OAAppearanceDefaultColors appearance] omniAlternateRedColor];
    return dot;
}

- (void)setUserInteractionEnabled:(BOOL)userInteractionEnabled
{
    [super setUserInteractionEnabled:userInteractionEnabled];
}

- (void)setSeekingAttention:(BOOL)seekingAttention
{
    if (seekingAttention == _seekingAttention) {
        return;
    }
    
    _seekingAttention = seekingAttention;
    
    if (seekingAttention) {
        [self setImage:self.attentionSeekingImage forState:UIControlStateNormal];
        self.attentionDot.hidden = NO;
    } else {
        [self setImage:self.normalImage forState:UIControlStateNormal];
        self.attentionDot.hidden = YES;
    }
}

- (void)attentionSeekingNeedDidChange:(NSNotification *)notification
{
    NSNumber *shouldSeekAttention = [notification.userInfo objectForKey:self.attentionKey];
    
    if (shouldSeekAttention != nil) {
        self.seekingAttention = shouldSeekAttention.boolValue;
    }
}

@end
