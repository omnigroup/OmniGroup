// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentTitleView.h"

#import <OmniFoundation/OFBindingPoint.h>
#import <OmniFileExchange/OFXAccountActivity.h>

RCS_ID("$Id$");

@interface OUIDocumentTitleView ()

@property (nonatomic, strong) UIButton *syncButton;
@property (nonatomic, strong) UIButton *documentTitleButton;
@property (nonatomic, strong) UILabel *documentTitleLabel;

@end

@implementation OUIDocumentTitleView
{
    NSTimer *_syncButtonIconAnimationTimer;
    NSUInteger _syncButtonIconAnimationState;
    BOOL _syncButtonIconAnimationLastLoop;
    
    BOOL _permanentConstraintsAdded;
    NSArray *_syncButtonRemovableConstraints;
}

static void _commonInit(OUIDocumentTitleView *self)
{
    self.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    
    self->_documentTitleLabel = [[UILabel alloc] init];
    self->_documentTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self->_documentTitleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self->_documentTitleLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self addSubview:self->_documentTitleLabel];
    
    self->_documentTitleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self->_documentTitleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self->_documentTitleButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self->_documentTitleButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self->_documentTitleButton addTarget:self action:@selector(_documentTitleButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self->_documentTitleButton.hidden = YES;
    [self addSubview:self->_documentTitleButton];
    
    self->_titleColor = [UIColor blackColor];
    [self _updateTitles];
    
    self->_syncButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self->_syncButton setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon"] forState:UIControlStateNormal];
    self->_syncButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self->_syncButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self->_syncButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    self->_syncButton.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Sync Now", @"OmniUIDocument", OMNI_BUNDLE, @"Presence toolbar item accessibility label.");
    [self->_syncButton addTarget:self action:@selector(_syncButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self->_syncButton.hidden = YES;
    [self addSubview:self->_syncButton];
    
    [self setNeedsUpdateConstraints];
    [self updateConstraintsIfNeeded];
    
#if 0 && defined(DEBUG_kyle)
    self.backgroundColor = [[UIColor purpleColor] colorWithAlphaComponent:0.4];
    self->_documentTitleButton.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.4];
    self->_documentTitleLabel.backgroundColor = [[UIColor blueColor] colorWithAlphaComponent:0.4];
    self->_syncButton.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.4];
#endif
    
    self.frame = (CGRect) {
        .origin = CGPointZero,
        .size = [self systemLayoutSizeFittingSize:UILayoutFittingCompressedSize]
    };
}

- (id)initWithFrame:(CGRect)frame;
{
    if ((self = [super initWithFrame:frame]))
        _commonInit(self);
    
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    if ((self = [super initWithCoder:aDecoder]))
        _commonInit(self);
    
    return self;
}

- (void)dealloc;
{
    if (_syncAccountActivity) {
        [_syncAccountActivity removeObserver:self forKeyPath:OFValidateKeyPath(_syncAccountActivity, isActive) context:SyncAccountActivityContext];
        [_syncAccountActivity removeObserver:self forKeyPath:OFValidateKeyPath(_syncAccountActivity, lastError) context:SyncAccountActivityContext];
    }
    
    [_syncButtonIconAnimationTimer invalidate];
}

#pragma mark - API

@synthesize syncAccountActivity=_syncAccountActivity;

- (OFXAccountActivity *)syncAccountActivity;
{
    return _syncAccountActivity;
}

- (void)setSyncAccountActivity:(OFXAccountActivity *)syncAccountActivity;
{
    if (_syncAccountActivity != syncAccountActivity) {
        [_syncAccountActivity removeObserver:self forKeyPath:OFValidateKeyPath(_syncAccountActivity, isActive) context:SyncAccountActivityContext];
        [_syncAccountActivity removeObserver:self forKeyPath:OFValidateKeyPath(_syncAccountActivity, lastError) context:SyncAccountActivityContext];
        
        _syncAccountActivity = syncAccountActivity;
        
        [_syncAccountActivity addObserver:self forKeyPath:OFValidateKeyPath(_syncAccountActivity, isActive) options:0 context:SyncAccountActivityContext];
        [_syncAccountActivity addObserver:self forKeyPath:OFValidateKeyPath(_syncAccountActivity, lastError) options:0 context:SyncAccountActivityContext];
        
        [self _updateSyncButtonIconForAccountActivity];
    }
}

@synthesize title=_title;

- (NSString *)title;
{
    return _title;
}

- (void)setTitle:(NSString *)title;
{
    _title = title;
    [self _updateTitles];
}

@synthesize titleCanBeTapped=_titleCanBeTapped;

- (BOOL)titleCanBeTapped;
{
    return _titleCanBeTapped;
}

- (void)setTitleCanBeTapped:(BOOL)flag;
{
    if (_titleCanBeTapped != flag) {
        _titleCanBeTapped = flag;
        
        if (_titleCanBeTapped) {
            _documentTitleLabel.hidden = YES;
            _documentTitleButton.hidden = NO;
        } else {
            _documentTitleButton.hidden = YES;
            _documentTitleLabel.hidden = NO;
        }
    }
    
    [self setNeedsLayout];
}

@synthesize titleColor=_titleColor;

- (UIColor *)titleColor;
{
    return _titleColor;
}

- (void)setTitleColor:(UIColor *)aColor;
{
    _titleColor = aColor;
    [self _updateTitles];
}

#pragma mark - UIView subclass

+ (BOOL)requiresConstraintBasedLayout;
{
    return YES;
}

- (void)updateConstraints;
{
    NSDictionary *views = @{@"syncButton" : _syncButton, @"documentTitleLabel" : _documentTitleLabel, @"documentTitleButton" : _documentTitleButton};
    
    if (!_syncButtonRemovableConstraints && !_syncButton.hidden) {
        if (!_syncButtonRemovableConstraints) {
            _syncButtonRemovableConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(0)-[syncButton][documentTitleLabel]" options:0 metrics:0 views:views];
        }
        
        [self addConstraints:_syncButtonRemovableConstraints];
    }
    
    if (!_permanentConstraintsAdded) {
        // Keep the label from spilling out of our size
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(0@999)-[documentTitleLabel]|" options:0 metrics:0 views:views]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(0@999)-[documentTitleLabel]-(0@999)-|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
        
        // Vertically center the label
        [self addConstraint:[NSLayoutConstraint constraintWithItem:_documentTitleLabel attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
        
        // Make the title button always the same size as the label
        [self addConstraint:[NSLayoutConstraint constraintWithItem:_documentTitleButton attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:_documentTitleLabel attribute:NSLayoutAttributeWidth multiplier:1 constant:0]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:_documentTitleButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:_documentTitleLabel attribute:NSLayoutAttributeHeight multiplier:1 constant:0]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:_documentTitleButton attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:_documentTitleLabel attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:_documentTitleButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:_documentTitleLabel attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
        
        // Keep the sync button from spilling out of our size
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(0@999)-[syncButton]-(0@999)-|" options:0 metrics:0 views:views]];
        
        // Vertically center the sync button
        [self addConstraint:[NSLayoutConstraint constraintWithItem:_syncButton attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
        
        _permanentConstraintsAdded = YES;
    }
    
    [super updateConstraints];
}

- (CGSize)sizeThatFits:(CGSize)size;
{
    CGSize fittingSize = [self systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    
#if 0 && defined(DEBUG_kyle)
    NSLog(@"-[%@ sizeThatFits:%@] >>> %@", self.shortDescription, NSStringFromCGSize(size), NSStringFromCGSize(fittingSize));
#endif
    
    return fittingSize;
}

#pragma mark - NSKeyValueObserving

static void *SyncAccountActivityContext = &SyncAccountActivityContext;

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == SyncAccountActivityContext) {
        OBASSERT(object == _syncAccountActivity);
        [self _updateSyncButtonIconForAccountActivity];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - Helpers

- (void)_updateTitles;
{
    NSString *plainTitle = _title ? _title : @"";
    NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:plainTitle attributes:@{NSForegroundColorAttributeName : _titleColor, NSFontAttributeName : [UIFont boldSystemFontOfSize:17.0f]}];
    _documentTitleLabel.attributedText = attributedTitle;
    [_documentTitleButton setAttributedTitle:attributedTitle forState:UIControlStateNormal];
}

- (void)_documentTitleButtonTapped:(id)sender;
{
    if ([_delegate respondsToSelector:@selector(documentTitleView:titleTapped:)])
        [_delegate documentTitleView:self titleTapped:sender];
}

- (void)_syncButtonTapped:(id)sender;
{
    if ([_delegate respondsToSelector:@selector(documentTitleView:syncButtonTapped:)])
        [_delegate documentTitleView:self syncButtonTapped:sender];
}

- (void)_updateSyncButtonIconForAccountActivity;
{
    if (!_syncAccountActivity) {
        _syncButton.hidden = YES;
    } else {
        _syncButton.hidden = NO;
    }
    
    [self setNeedsUpdateConstraints];
    
    if ([_syncAccountActivity lastError] != nil) {
        [_syncButtonIconAnimationTimer invalidate];
        _syncButtonIconAnimationTimer = nil;
        if ([[_syncAccountActivity lastError] causedByUnreachableHost]) {
            [_syncButton setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon-Offline.png"] forState:UIControlStateNormal];
        } else {
            [_syncButton setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon-Error.png"] forState:UIControlStateNormal];
        }
    } else if ([_syncAccountActivity isActive]) {
        if (!_syncButtonIconAnimationTimer) {
            _syncButtonIconAnimationState = 0;
            _syncButtonIconAnimationLastLoop = NO;
            [self _updateSyncButtonAnimationState];
            [self _rescheduleAnimationTimer];
        }
    } else {
        if (_syncButtonIconAnimationTimer) {
            _syncButtonIconAnimationLastLoop = YES;
            [self _rescheduleAnimationTimer];
        } else
            [_syncButton setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon.png"] forState:UIControlStateNormal];
    }
}

- (void)_updateSyncButtonAnimationState;
{
    _syncButtonIconAnimationState++;
    if (_syncButtonIconAnimationState > 3) {
        if (_syncButtonIconAnimationLastLoop) {
            [_syncButtonIconAnimationTimer invalidate];
            _syncButtonIconAnimationTimer = nil;
            _syncButtonIconAnimationState = 0;
            [_syncButton setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon.png"] forState:UIControlStateNormal];
            return;
        }
        _syncButtonIconAnimationState = 1;
    }
    [_syncButton setImage:[UIImage imageNamed:[NSString stringWithFormat:@"OmniPresenceToolbarIconAnimation-%lu.png", _syncButtonIconAnimationState]] forState:UIControlStateNormal];
}

- (void)_rescheduleAnimationTimer;
{
    NSTimeInterval newTimeInterval = (_syncButtonIconAnimationLastLoop ? 0.15 : 0.45);
    NSDate *newFireDate = nil;
    if (_syncButtonIconAnimationTimer != nil) {
        NSTimeInterval oldTimeInterval = [_syncButtonIconAnimationTimer timeInterval];
        if (oldTimeInterval == newTimeInterval)
            return; // No change needed
        
        NSDate *oldFireDate = [_syncButtonIconAnimationTimer fireDate];
        newFireDate = [oldFireDate dateByAddingTimeInterval:newTimeInterval - oldTimeInterval];
    }
    [_syncButtonIconAnimationTimer invalidate];
    _syncButtonIconAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:newTimeInterval target:self selector:@selector(_updateSyncButtonAnimationState) userInfo:nil repeats:YES];
    if (newFireDate != nil)
        [_syncButtonIconAnimationTimer setFireDate:newFireDate];
}

@end
