// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentTitleView.h>

#import <OmniFoundation/OFBindingPoint.h>
#import <OmniFileExchange/OFXAccountActivity.h>
#import <OmniUIDocument/OmniUIDocumentAppearance.h>
#import <OmniUIDocument/OUIDocumentAppController.h>

RCS_ID("$Id$");

@interface OUIDocumentTitleView ()

@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, readwrite, strong) UIButton *closeDocumentButton;
@property (nonatomic, strong) UIButton *syncButton;
@property (nonatomic, strong) UIButton *documentTitleButton;
@property (nonatomic, strong) UILabel *documentTitleLabel;

@property (nonatomic, assign) BOOL syncButtonShowingActiveState;
@property (nonatomic, assign) NSTimeInterval syncButtonActivityStartedTimeInterval;
@property (nonatomic, assign) NSTimeInterval syncButtonLastActivityTimeInterval;
@property (nonatomic, strong) NSTimer *syncButtonActivityFinishedTimer;

@property (nonatomic, readwrite, strong) UIBarButtonItem *closeDocumentBarButtonItem;
@property (nonatomic, readwrite, strong) UIBarButtonItem *syncBarButtonItem;

@end

@implementation OUIDocumentTitleView

static void _commonInit(OUIDocumentTitleView *self)
{
    self.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    
    self->_documentTitleLabel = [[UILabel alloc] init];
    self->_documentTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self->_documentTitleLabel.textAlignment = NSTextAlignmentCenter;
    [self->_documentTitleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self->_documentTitleLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    
    self->_documentTitleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self->_documentTitleButton.translatesAutoresizingMaskIntoConstraints = NO;
    self->_documentTitleButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self->_documentTitleButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self->_documentTitleButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self->_documentTitleButton addTarget:self action:@selector(_documentTitleButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self->_documentTitleButton.hidden = YES;
    self->_documentTitleButton.accessibilityHint = NSLocalizedStringFromTableInBundle(@"Edits the document's title.", @"OmniUIDocument", OMNI_BUNDLE, @"title view edit button item accessibility hint.");
    
    self->_titleColor = [UIColor blackColor];
    [self _updateTitles];
    
    UIImage *syncImage = [UIImage imageNamed:@"OmniPresenceToolbarIcon" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    self->_syncButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self->_syncButton setImage:syncImage forState:UIControlStateNormal];
    self->_syncButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self->_syncButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self->_syncButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    self->_syncButton.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Sync Now", @"OmniUIDocument", OMNI_BUNDLE, @"Presence toolbar item accessibility label.");
    [self->_syncButton addTarget:self action:@selector(_syncButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self->_syncButton.hidden = YES;
    
    UIImage *closeDocumentImage = [UIImage imageNamed:@"OUIToolbarDocumentClose" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    self->_closeDocumentButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self->_closeDocumentButton setImage:closeDocumentImage forState:UIControlStateNormal];
    self->_closeDocumentButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self->_closeDocumentButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self->_closeDocumentButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    self->_closeDocumentButton.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Close Document", @"OmniUIDocument", OMNI_BUNDLE, @"Close Document toolbar item accessibility label.");
    [self->_closeDocumentButton addTarget:self action:@selector(_closeDocument:) forControlEvents:UIControlEventTouchUpInside];
    self->_closeDocumentButton.hidden = YES;

    self.closeDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIToolbarDocumentClose" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil]
                                     style:UIBarButtonItemStylePlain target:self action:@selector(_closeDocument:)];
    self.closeDocumentBarButtonItem.accessibilityIdentifier = @"BackToDocuments";
    
    self.syncBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(_syncButtonTapped:)];

    self->_hideTitle = YES;
    
#if 0 && defined(DEBUG_rachael)
    self.backgroundColor = [[UIColor purpleColor] colorWithAlphaComponent:0.4];
    self->_documentTitleButton.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.4];
    self->_documentTitleLabel.backgroundColor = [[UIColor blueColor] colorWithAlphaComponent:0.4];
    self->_syncButton.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.4];
#endif
    
    
    self->_stackView = [[UIStackView alloc] init];
    self->_stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self->_stackView.axis = UILayoutConstraintAxisHorizontal;
    self->_stackView.alignment = UIStackViewAlignmentCenter;
    self->_stackView.spacing = 8.0f;
    [self addSubview:self->_stackView];

    [self->_stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = YES;
    [self->_stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
    [self->_stackView.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
    [self->_stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = YES;

    [self->_stackView addArrangedSubview:self->_closeDocumentButton];
    [self->_stackView addArrangedSubview:self->_documentTitleButton];
    [self->_stackView addArrangedSubview:self->_documentTitleLabel];
    [self->_stackView addArrangedSubview:self->_syncButton];
    
    self.frame = (CGRect) {
        .origin = CGPointZero,
        .size = (CGSize) {
            .width = 0, // Width will be resized via UINavigationBar during its layout.
            .height = MAX(syncImage.size.height, closeDocumentImage.size.height) // UINavigationBar will never change our size, so we need to set that up here.
        }
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

- (BOOL)shouldShowCloseDocumentButton {
    return !self.closeDocumentButton.hidden;
}

- (void)setShouldShowCloseDocumentButton:(BOOL)shouldShowCloseDocumentButton {
    self.closeDocumentButton.hidden = !shouldShowCloseDocumentButton;
}

#pragma mark - API

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

- (void)setTitle:(NSString *)title;
{
    if ([_title isEqualToString:title]) {
        return;
    }
    
    _title = title;
    [self _updateTitles];
}

- (void)setTitleCanBeTapped:(BOOL)flag;
{
    if (_titleCanBeTapped != flag) {
        _titleCanBeTapped = flag;
        [self _updateTitleVisibility];
    }
    
    [self setNeedsLayout];
}

- (void)setTitleColor:(UIColor *)aColor;
{
    _titleColor = aColor;
    [self _updateTitles];
}

- (void)setHideTitle:(BOOL)hideTitle;
{
    _hideTitle = hideTitle;
    [self _updateTitleVisibility];
}

- (void)setHideSyncButton:(BOOL)hideSyncButton {
    _hideSyncButton = hideSyncButton;
    
    [self _updateSyncButtonIconForAccountActivity];
}
#pragma mark - UIView subclass

+ (BOOL)requiresConstraintBasedLayout;
{
    return YES;
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
    
    // Make sure the title didn't get too long and bleed into the bar button items
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)_updateTitleVisibility;
{
    if (self.hideTitle == NO) {
        if (_titleCanBeTapped) {
            _documentTitleLabel.hidden = YES;
            _documentTitleButton.hidden = NO;
        } else {
            _documentTitleButton.hidden = YES;
            _documentTitleLabel.hidden = NO;
        }
    } else {
        _documentTitleButton.hidden = YES;
        _documentTitleLabel.hidden = YES;
    }
}

- (void)_documentTitleButtonTapped:(id)sender;
{
    if ([_delegate respondsToSelector:@selector(documentTitleView:titleTapped:)])
        [_delegate documentTitleView:self titleTapped:sender];
}

- (void)_closeDocument:(id)sender {
    OUIDocumentAppController *docAppController = (OUIDocumentAppController *)[(UIApplication *)[UIApplication sharedApplication] delegate];
    [docAppController closeDocument:sender];
}

- (void)_syncButtonTapped:(id)sender;
{
    if ([_delegate respondsToSelector:@selector(documentTitleView:syncButtonTapped:)])
        [_delegate documentTitleView:self syncButtonTapped:sender];
}

- (void)_updateSyncButtonIconForAccountActivity;
{
    if (self.hideSyncButton) {
        self.syncButton.hidden = YES;
        return;
    }
    
    if (!_syncAccountActivity) {
        _syncButton.hidden = YES;
        self.syncBarButtonItem.image = nil;
    } else {
        _syncButton.hidden = NO;
    }
    
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

@end
