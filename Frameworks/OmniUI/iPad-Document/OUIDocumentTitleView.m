// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentTitleView.h>

#import <OmniFoundation/OFBindingPoint.h>
#import <OmniFileExchange/OFXAccountActivity.h>
#import <OmniUIDocument/OmniUIDocumentAppearance.h>

RCS_ID("$Id$");

typedef enum{
    TitleActiveViewsNone,
    TitleActiveViewsTitleOnly,
    TitleActiveViewsButtonOnly,
    TitleActiveViewsAll
}TitleActiveViews;

@interface OUIDocumentTitleView ()

@property (nonatomic, strong) UIButton *syncButton;
@property (nonatomic, strong) UIButton *documentTitleButton;
@property (nonatomic, strong) UILabel *documentTitleLabel;
@property BOOL generatedConstraints;

@property (nonatomic, strong) NSMutableArray *buttonOnlyConstraints;
@property (nonatomic, strong) NSMutableArray *titleOnlyConstraints;
@property (nonatomic, strong) NSMutableArray *buttonAndTitleConstraints;
@property (nonatomic, strong) NSArray *activeConstraints;
@end

@implementation OUIDocumentTitleView
{
    BOOL _syncButtonShowingActiveState;
    NSTimeInterval _syncButtonActivityStartedTimeInterval;
    NSTimeInterval _syncButtonLastActivityTimeInterval;
    NSTimer *_syncButtonActivityFinishedTimer;
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
    self->_documentTitleButton.accessibilityHint = NSLocalizedStringFromTableInBundle(@"Edits the document's title.", @"OmniUIDocument", OMNI_BUNDLE, @"title view edit button item accessibility hint.");
    
    [self addSubview:self->_documentTitleButton];
    
    self->_titleColor = [UIColor blackColor];
    [self _updateTitles];
    
    self->_syncButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self->_syncButton setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
    self->_syncButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self->_syncButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self->_syncButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    self->_syncButton.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Sync Now", @"OmniUIDocument", OMNI_BUNDLE, @"Presence toolbar item accessibility label.");
    [self->_syncButton addTarget:self action:@selector(_syncButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self->_syncButton.hidden = YES;
    [self addSubview:self->_syncButton];
    
    self.syncBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(_syncButtonTapped:)];

    self->_hideTitle = YES;
    self->_generatedConstraints = NO;

    [self setNeedsUpdateConstraints];
    [self updateConstraintsIfNeeded];
    
#if 0 && defined(DEBUG_rachael)
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
    
    [_syncButtonActivityFinishedTimer invalidate];
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
        [self _updateTitleVisibility];
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

@synthesize hideTitle = _hideTitle;
- (BOOL)hideTitle;
{
    return _hideTitle;
}

- (void)setHideTitle:(BOOL)hideTitle;
{
    _hideTitle = hideTitle;
    [self _updateTitleVisibility];
}
#pragma mark - UIView subclass

+ (BOOL)requiresConstraintBasedLayout;
{
    return YES;
}

- (void)updateConstraints;
{
    [self _createConstraintsIfNeeded];
    [super updateConstraints];
}

- (CGSize)sizeThatFits:(CGSize)size;
{
    CGSize fittingSize = [self systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
#if 0 && defined(DEBUG_rachael)
    NSLog(@"subviews = %@", self.subviews);
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

- (void)_activateConstraintsForTitleActiveViews:(TitleActiveViews)titleActiveViews{
    NSArray *constraintsToActivate;
    switch (titleActiveViews) {
        case TitleActiveViewsNone:
            constraintsToActivate = nil;
            break;
        case TitleActiveViewsAll:
            constraintsToActivate = self.buttonAndTitleConstraints;
            break;
        case TitleActiveViewsButtonOnly:
            constraintsToActivate = self.buttonOnlyConstraints;
            break;
        case TitleActiveViewsTitleOnly:
            constraintsToActivate = self.titleOnlyConstraints;
            break;
    }
    if (constraintsToActivate != self.activeConstraints) {
        [NSLayoutConstraint deactivateConstraints:self.activeConstraints];
        self.activeConstraints = constraintsToActivate;
        [NSLayoutConstraint activateConstraints:constraintsToActivate];
    }
}

- (void)_updateTitleVisibility;
{
    if (self.hideTitle == NO) {
        if ([self.documentTitleLabel superview] == nil) {
            [self addSubview:self.documentTitleLabel];
        }

        if ([self.documentTitleButton superview] == nil) {
            [self addSubview:self.documentTitleButton];
        }

        if (_titleCanBeTapped) {
            _documentTitleLabel.hidden = YES;
            _documentTitleButton.hidden = NO;
        } else {
            _documentTitleButton.hidden = YES;
            _documentTitleLabel.hidden = NO;
        }

        if (self.syncButton.hidden == YES) {
            [self _activateConstraintsForTitleActiveViews:TitleActiveViewsTitleOnly];
        } else {
            [self _activateConstraintsForTitleActiveViews:TitleActiveViewsAll];
        }

    } else {
        _documentTitleButton.hidden = YES;
        _documentTitleLabel.hidden = YES;

        if (self.syncButton.hidden == YES) {
            [self _activateConstraintsForTitleActiveViews:TitleActiveViewsNone];
        } else {
            [self _activateConstraintsForTitleActiveViews:TitleActiveViewsButtonOnly];
        }
        [self.documentTitleButton removeFromSuperview];
        [self.documentTitleLabel removeFromSuperview];

    }
    [self setNeedsUpdateConstraints];
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
        [_syncButton removeFromSuperview];
        
        self.syncBarButtonItem.image = nil;

        if (self.hideTitle == YES) {
            [self _activateConstraintsForTitleActiveViews:TitleActiveViewsTitleOnly];
        } else {
            [self _activateConstraintsForTitleActiveViews:TitleActiveViewsNone];
        }
    } else {
        _syncButton.hidden = NO;
        [self addSubview:_syncButton];

        if (self.hideTitle == YES) {
            [self _activateConstraintsForTitleActiveViews:TitleActiveViewsButtonOnly];
        } else {
            [self _activateConstraintsForTitleActiveViews:TitleActiveViewsAll];
        }
    }
    
    [self setNeedsUpdateConstraints];
    
    if ([_syncAccountActivity lastError] != nil) {
        _syncButtonShowingActiveState = NO;
        [_syncButtonActivityFinishedTimer invalidate];
        _syncButtonActivityFinishedTimer = nil;
        if ([[_syncAccountActivity lastError] causedByUnreachableHost]) {
            [_syncButton setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon-Offline" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            self.syncBarButtonItem.image = [UIImage imageNamed:@"OmniPresenceToolbarIcon-Offline" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
        } else {
            [_syncButton setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon-Error" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            self.syncBarButtonItem.image = [UIImage imageNamed:@"OmniPresenceToolbarIcon-Error" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
        }
    } else if ([_syncAccountActivity isActive]) {
        if (!_syncButtonShowingActiveState) {
            _syncButtonShowingActiveState = YES;
            _syncButtonActivityStartedTimeInterval = [NSDate timeIntervalSinceReferenceDate];
            [_syncButton setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon-Active" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            self.syncBarButtonItem.image = [UIImage imageNamed:@"OmniPresenceToolbarIcon-Active" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
        }
        _syncButtonLastActivityTimeInterval = [NSDate timeIntervalSinceReferenceDate];
        
        [_syncButtonActivityFinishedTimer invalidate];
        _syncButtonActivityFinishedTimer = nil;
    } else if (_syncButtonShowingActiveState && _syncButtonActivityFinishedTimer == nil) {
        // Prepare to turn off the active state on the icon. Leave it on at least a minimum time since the very start and a (smaller) minimum time since the last activity (in case the state toggles several times).
        
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval timeSinceStart = now - _syncButtonActivityStartedTimeInterval;
        NSTimeInterval timeSinceLastActivity = now - _syncButtonLastActivityTimeInterval;

        NSTimeInterval remainingTimeSinceStart = [OmniUIDocumentAppearance appearance].documentSyncMinimumVisiblityFromActivityStartTimeInterval - timeSinceStart;
        NSTimeInterval remainingTimeSinceLastActivity = [OmniUIDocumentAppearance appearance].documentSyncMinimumVisiblityFromLastActivityTimeInterval - timeSinceLastActivity;
        
        NSTimeInterval remainingTime = MAX3(0, remainingTimeSinceStart, remainingTimeSinceLastActivity);

        _syncButtonShowingActiveState = NO;
        
        _syncButtonActivityFinishedTimer = [NSTimer scheduledTimerWithTimeInterval:remainingTime target:self selector:@selector(_activityFinishedTimerFired:) userInfo:nil repeats:NO];
    }
}

- (void)_activityFinishedTimerFired:(NSTimer *)timer;
{
    OBPRECONDITION(_syncButtonActivityFinishedTimer == timer);
    
    [_syncButtonActivityFinishedTimer invalidate];
    _syncButtonActivityFinishedTimer = nil;
    
    _syncButtonShowingActiveState = NO;
    [_syncButton setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
    self.syncBarButtonItem.image = [UIImage imageNamed:@"OmniPresenceToolbarIcon" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

- (void)_createConstraintsIfNeeded;
{
    if (!self.generatedConstraints) {
        self.generatedConstraints = YES;
        NSDictionary *views = @{@"syncButton" : _syncButton, @"documentTitleLabel" : _documentTitleLabel, @"documentTitleButton" : _documentTitleButton};
        
        // ***buttonOnlyConstraints
        OBASSERT(self.buttonOnlyConstraints == nil);
        self.buttonOnlyConstraints = [NSMutableArray array];
        
        // Pin the button to the superview
        [self.buttonOnlyConstraints addObject:[NSLayoutConstraint constraintWithItem:self.syncButton attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeading multiplier:1.0 constant:0.0]];
        [self.buttonOnlyConstraints addObject:[NSLayoutConstraint constraintWithItem:self.syncButton attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:0.0]];
        [self.buttonOnlyConstraints addObject:[NSLayoutConstraint constraintWithItem:self.syncButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTop multiplier:1.0 constant:0.0]];
        [self.buttonOnlyConstraints addObject:[NSLayoutConstraint constraintWithItem:self.syncButton attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0]];
        
        // ***titleOnlyConstraints
        OBASSERT(self.titleOnlyConstraints == nil);
        self.titleOnlyConstraints = [NSMutableArray array];
        
        // Keep the label from spilling out of our size
        [self.titleOnlyConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(0@999)-[documentTitleLabel]|" options:0 metrics:0 views:views]];
        [self.titleOnlyConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(0@999)-[documentTitleLabel]-(0@999)-|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
        
        // Vertically center the label
        [self.titleOnlyConstraints addObject:[NSLayoutConstraint constraintWithItem:_documentTitleLabel attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
        
        // Make the title button always the same size as the label
        [self.titleOnlyConstraints addObject:[NSLayoutConstraint constraintWithItem:_documentTitleButton attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:_documentTitleLabel attribute:NSLayoutAttributeWidth multiplier:1 constant:0]];
        [self.titleOnlyConstraints addObject:[NSLayoutConstraint constraintWithItem:_documentTitleButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:_documentTitleLabel attribute:NSLayoutAttributeHeight multiplier:1 constant:0]];
        [self.titleOnlyConstraints addObject:[NSLayoutConstraint constraintWithItem:_documentTitleButton attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:_documentTitleLabel attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
        [self.titleOnlyConstraints addObject:[NSLayoutConstraint constraintWithItem:_documentTitleButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:_documentTitleLabel attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
        
        [self.titleOnlyConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(0)-[documentTitleLabel]" options:0 metrics:0 views:views]];
        
        
        // ***buttonAndTitleConstraints
        OBASSERT(self.buttonAndTitleConstraints == nil);
        self.buttonAndTitleConstraints = [NSMutableArray array];
        
        // line up sync button and title
        [self.buttonAndTitleConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(0)-[syncButton]-(7)-[documentTitleLabel]" options:0 metrics:0 views:views]];
        
        // Keep the label from spilling out of our size
        [self.buttonAndTitleConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(0@999)-[documentTitleLabel]|" options:0 metrics:0 views:views]];
        [self.buttonAndTitleConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(0@999)-[documentTitleLabel]-(0@999)-|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
        
        // Vertically center the label
        [self.buttonAndTitleConstraints addObject:[NSLayoutConstraint constraintWithItem:_documentTitleLabel attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
        
        // Make the title button always the same size as the label
        [self.buttonAndTitleConstraints addObject:[NSLayoutConstraint constraintWithItem:_documentTitleButton attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:_documentTitleLabel attribute:NSLayoutAttributeWidth multiplier:1 constant:0]];
        [self.buttonAndTitleConstraints addObject:[NSLayoutConstraint constraintWithItem:_documentTitleButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:_documentTitleLabel attribute:NSLayoutAttributeHeight multiplier:1 constant:0]];
        [self.buttonAndTitleConstraints addObject:[NSLayoutConstraint constraintWithItem:_documentTitleButton attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:_documentTitleLabel attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
        [self.buttonAndTitleConstraints addObject:[NSLayoutConstraint constraintWithItem:_documentTitleButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:_documentTitleLabel attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
        
        // Keep the sync button from spilling out of our size
        [self.buttonAndTitleConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(0@999)-[syncButton]-(0@999)-|" options:0 metrics:0 views:views]];
        
        // Vertically center the sync button
        [self.buttonAndTitleConstraints addObject:[NSLayoutConstraint constraintWithItem:_syncButton attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
    }
}

@end
