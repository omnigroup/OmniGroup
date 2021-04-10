// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentTitleView.h>

#import <OmniFoundation/OFBindingPoint.h>
#import <OmniFileExchange/OFXAccountActivity.h>
#import <OmniUIDocument/OmniUIDocumentAppearance.h>
#import <OmniUIDocument/OUIDocumentSceneDelegate.h>

RCS_ID("$Id$");

@interface OUIDocumentTitleView ()

@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, readwrite, strong) UIButton *closeDocumentButton;
@property (nonatomic, strong) UIButton *documentTitleButton;
@property (nonatomic, strong) UILabel *documentTitleLabel;

@property (nonatomic, readwrite, strong) UIBarButtonItem *closeDocumentBarButtonItem;

@end

@implementation OUIDocumentTitleView

static void _commonInit(OUIDocumentTitleView *self)
{
    self.autoresizingMask = UIViewAutoresizingFlexibleHeight;
#ifdef DEBUG_kc0
    self.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.1];
#endif

    NSBundle *bundle = OMNI_BUNDLE;

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
    self->_documentTitleButton.accessibilityHint = NSLocalizedStringFromTableInBundle(@"Edits the document's title.", @"OmniUIDocument", bundle, @"title view edit button item accessibility hint.");
    
    self->_titleColor = [UIColor labelColor];
    [self _updateTitles];
    
    UIImage *closeDocumentImage = [UIImage imageNamed:@"OUIToolbarDocuments" inBundle:bundle compatibleWithTraitCollection:nil];
    self->_closeDocumentButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self->_closeDocumentButton setImage:closeDocumentImage forState:UIControlStateNormal];
    self->_closeDocumentButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self->_closeDocumentButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self->_closeDocumentButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    self->_closeDocumentButton.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Close Document", @"OmniUIDocument", bundle, @"Close Document toolbar item accessibility label.");
    [self->_closeDocumentButton addTarget:self action:@selector(_closeDocument:) forControlEvents:UIControlEventTouchUpInside];
    self->_closeDocumentButton.hidden = YES;

    self.closeDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithImage:closeDocumentImage
                                     style:UIBarButtonItemStylePlain target:self action:@selector(_closeDocument:)];
    self.closeDocumentBarButtonItem.accessibilityIdentifier = @"BackToDocuments";
    
    self->_hideTitle = YES;
    
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

    self.frame = (CGRect) {
        .origin = CGPointZero,
        .size = (CGSize) {
            .width = 0, // Width will be resized via UINavigationBar during its layout.
            .height = closeDocumentImage.size.height // UINavigationBar will never change our size, so we need to set that up here.
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

- (BOOL)shouldShowCloseDocumentButton {
    return !self.closeDocumentButton.hidden;
}

- (void)setShouldShowCloseDocumentButton:(BOOL)shouldShowCloseDocumentButton {
    self.closeDocumentButton.hidden = !shouldShowCloseDocumentButton;
}

#pragma mark - API

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
    id<OUIDocumentTitleViewDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(documentTitleView:titleTapped:)])
        [delegate documentTitleView:self titleTapped:sender];
}

- (void)_closeDocument:(id)sender {
    OUIDocumentSceneDelegate *sceneDelegate = [OUIDocumentSceneDelegate documentSceneDelegateForView:self];
    [sceneDelegate closeDocument:sender];
}

@end
