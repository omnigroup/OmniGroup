// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerItemView.h>

#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUIDocument/OUIDocumentPreviewView.h>
#import <OmniUIDocument/OUIDocumentPickerItemMetadataView.h>
#import <OmniUI/OUIFeatures.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUI/UIGestureRecognizer-OUIExtensions.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUIDrawing.h>

#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIDocumentParameters.h"

RCS_ID("$Id$");

NSString * const OUIDocumentPickerItemViewPreviewsDidLoadNotification = @"OUIDocumentPickerItemViewPreviewsDidLoadNotification";

@interface OUIDocumentPickerItemView () <UIDragInteractionDelegate>
- (void)_loadOrDeferLoadingPreviewsForViewsStartingAtIndex:(NSUInteger)index;
@property (nonatomic, strong) NSArray *cachedCustomAccessibilityActions;
@property (nonatomic, strong) NSTimer *hackyTimerToGetRenamingToWorkWithProKeyboard;
@end

@interface OUIDocumentPickerPreviewViewContainer : UIView
@property (readonly) NSArray *sortedPreviewViews;
@end

@implementation OUIDocumentPickerPreviewViewContainer
{
    NSMutableArray *_sortedPreviewViews;
}

- (void)didAddSubview:(UIView *)subview;
{
    OBPRECONDITION(![_sortedPreviewViews containsObject:subview]);
    
    if ([subview isKindOfClass:[OUIDocumentPreviewView class]]) {
        if (!_sortedPreviewViews)
            _sortedPreviewViews = [[NSMutableArray alloc] init];
        
        NSUInteger insertionIndex = [_sortedPreviewViews indexOfObject:subview inSortedRange:NSMakeRange(0, _sortedPreviewViews.count) options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(id obj1, id obj2) {
            NSUInteger tag1 = ((UIView *)obj1).tag;
            NSUInteger tag2 = ((UIView *)obj2).tag;
            if (tag1 == tag2)
                return NSOrderedSame;
            else if (tag2 > tag1)
                return NSOrderedAscending;
            else
                return NSOrderedDescending;
        }];
        
        [_sortedPreviewViews insertObject:subview atIndex:insertionIndex];
        [(OUIDocumentPickerItemView *)self.superview _loadOrDeferLoadingPreviewsForViewsStartingAtIndex:insertionIndex];
    }
    
    [super didAddSubview:subview];
}

- (void)willRemoveSubview:(UIView *)subview;
{
    if ([subview isKindOfClass:[OUIDocumentPreviewView class]]) {
        OBPRECONDITION([_sortedPreviewViews containsObject:subview]);
        NSUInteger firstIndex = [_sortedPreviewViews indexOfObject:subview];
        if (firstIndex != NSNotFound) {
            [_sortedPreviewViews removeObject:subview];
            [(OUIDocumentPickerItemView *)self.superview _loadOrDeferLoadingPreviewsForViewsStartingAtIndex:firstIndex];
        }
    }
    
    [super willRemoveSubview:subview];
}

@end

#pragma mark -

@implementation OUIDocumentPickerItemView
{
    ODSItem *_item;
    
    OUIDocumentPickerPreviewViewContainer *_contentView;
    OUIDocumentPickerItemMetadataView *_metadataView;
    UIView *_hairlineBorderView;
    UIView *_selectionBorderView;

    OUIDocumentPickerItemViewDraggingState _draggingState;
    
    BOOL _isEditingName;
    BOOL _deleting;
    BOOL _selected;
    BOOL _deferLoadingPreviews;
    BOOL _containerIsSelecting;
}

static id _commonInit(OUIDocumentPickerItemView *self)
{
    if (!self.metadataView) {
        [self createSubviews];
    }
    [self.metadataView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(metaDataTapped:)]];
    [self applyToViewTree:^OUIViewVisitorResult(UIView *view) {
        if (view != self) {
            view.translatesAutoresizingMaskIntoConstraints = NO;
        }
        if (view == self.metadataView.transferProgressView) {
            return OUIViewVisitorResultSkipSubviews;  // otherwise, we turn off layout that UIKit is depending on
        } else {
            return OUIViewVisitorResultContinue;
        }
    }];
    [NSLayoutConstraint activateConstraints:[self constraintsForBasicLayout]];
    
    self.isAccessibilityElement = YES;
    self.contentView.userInteractionEnabled = NO;
    OUIDocumentPreviewViewSetNormalBorder(self->_hairlineBorderView);
    self->_hairlineBorderView.userInteractionEnabled = NO;
    
    [self->_metadataView.nameTextField addTarget:self action:@selector(_nameTextFieldEditingDidBegin:) forControlEvents:UIControlEventEditingDidBegin];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardWillShow) name:UIKeyboardWillShowNotification object:nil];
    [self->_metadataView.nameTextField addTarget:self action:@selector(_nameTextFieldEndedEditing:) forControlEvents:UIControlEventEditingDidEnd];

    [self _updateRasterizesLayer];
    
    [self _setupAccessibilityActions];

    UIDragInteraction *dragInteraction = [[UIDragInteraction alloc] initWithDelegate:self];
    [self addInteraction:dragInteraction];

    return self;
}

- (void)metaDataTapped:(id)sender
{
    if ([self.metadataView isEditing]) {
        return;
    } else {
        [self detachMetaDataView];
        [self.superview setNeedsLayout];
        [self.superview layoutIfNeeded];  // without forcing layout, the becomeFirstResponder call will crash
        [self.metadataView.nameTextField becomeFirstResponder];
    }
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    [self createSubviews];
    return _commonInit(self);
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    if (!(self = [super initWithCoder:aDecoder]))
        return nil;
    return _commonInit(self);
}

- (void)createSubviews
{
    OUIDocumentPickerPreviewViewContainer *contentView = [[OUIDocumentPickerPreviewViewContainer alloc] initWithFrame:self.bounds];
        contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self addSubview:contentView];
    self->_contentView = contentView;
    
    self->_metadataView = [[OUIDocumentPickerItemMetadataView alloc] initWithFrame:CGRectZero];
    self->_metadataView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;

    [self insertSubview:self->_metadataView aboveSubview:self->_contentView];

    _statusImageView = [[UIImageView alloc] initWithImage:nil];
    _statusImageView.userInteractionEnabled = NO;
    [self addSubview:_statusImageView];
    
    // We set the border on this view rather than the whole view so that it doesn't draw atop the status image (the layer's border goes above all the sublayers instead of just with the layer's content, which is silly, but...)
    self->_hairlineBorderView = [[UIView alloc] init];
    [self insertSubview:self->_hairlineBorderView aboveSubview:self->_metadataView];
}

- (void)dealloc;
{
    [self stopObservingItem:_item];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
}

@synthesize item = _item;
- (void)setItem:(id)item;
{
    if (_item == item)
        return;
    
    if (_item)
        [self stopObservingItem:_item];
    
    _item = item;
    
    if (_item)
        [self startObservingItem:_item];
    
    [self itemChanged];
}

static unsigned ItemContext;

- (void)startObservingItem:(id)item;
{
    [item addObserver:self forKeyPath:ODSItemNameBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:ODSItemSelectedBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:ODSItemUserModificationDateBinding options:0 context:&ItemContext];
    
    [item addObserver:self forKeyPath:ODSItemIsDownloadedBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:ODSItemIsDownloadingBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:ODSItemIsUploadedBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:ODSItemIsUploadingBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:ODSItemPercentDownloadedBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:ODSItemPercentUploadedBinding options:0 context:&ItemContext];
}

- (void)stopObservingItem:(id)item;
{
    [item removeObserver:self forKeyPath:ODSItemNameBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:ODSItemSelectedBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:ODSItemUserModificationDateBinding context:&ItemContext];

    [item removeObserver:self forKeyPath:ODSItemIsDownloadedBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:ODSItemIsDownloadingBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:ODSItemIsUploadedBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:ODSItemIsUploadingBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:ODSItemPercentDownloadedBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:ODSItemPercentUploadedBinding context:&ItemContext];
}

- (OUIDocumentPreviewArea)previewArea;
{
    return OUIDocumentPreviewAreaLarge;
}

@synthesize draggingState = _draggingState;
- (void)setDraggingState:(OUIDocumentPickerItemViewDraggingState)draggingState;
{
    if (_draggingState == draggingState)
        return;
    
    _draggingState = draggingState;
    [self setNeedsLayout];
}

@synthesize highlighted = _highlighted;
- (void)setHighlighted:(BOOL)highlighted;
{
    if (_highlighted == highlighted)
        return;
    
    _highlighted = highlighted;
    for (OUIDocumentPreviewView *previewView in _contentView.sortedPreviewViews)
        previewView.highlighted = highlighted;
}

- (UIImage *)statusImage;
{
    return _statusImageView.image;
}
- (void)setStatusImage:(UIImage *)image;
{
    if (self.statusImage == image)
        return;
    
    if (image) {
        _statusImageView.image = image;
        _statusImageView.hidden = NO;
    } else {
        _statusImageView.hidden = YES;
    }
    
    [self setNeedsLayout];
}

- (BOOL)showsProgress;
{
    return _metadataView.showsProgress;
}
- (void)setShowsProgress:(BOOL)showsProgress;
{
    _metadataView.showsProgress = showsProgress;
}

- (double)progress;
{
    return _metadataView.progress;
}
- (void)setProgress:(double)progress;
{
    _metadataView.progress = progress;
}

static NSString * const EditingAnimationKey = @"editingAnimation";

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
{
    _containerIsSelecting = editing;
    [self _updateMetadataInteraction];
}

@synthesize shrunken = _shrunken;
- (void)setShrunken:(BOOL)shrunken;
{
    if (_shrunken == shrunken)
        return;
    
    _shrunken = shrunken;

    static NSString * const kShrunkenTransformKey = @"shrunkenTransform";

    CALayer *layer = self.layer;
    if ([UIView areAnimationsEnabled] == NO) {
        [layer removeAnimationForKey:kShrunkenTransformKey];
        self.alpha = _shrunken ? 0 : 1;
        return;
    }
    
    CATransform3D shrunkenTransform = CATransform3DMakeScale(0.001, 0.001, 1.0);
    
    // We currently assume that we aren't interrupting the animation partway through
    if (_shrunken) {
        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"transform"];
        anim.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
        anim.toValue = [NSValue valueWithCATransform3D:shrunkenTransform];
        anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        anim.fillMode = kCAFillModeForwards;
        [layer addAnimation:anim forKey:kShrunkenTransformKey];
        
        self.alpha = 0;
    } else {
        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"transform"];
        anim.fromValue = [NSValue valueWithCATransform3D:shrunkenTransform];
        anim.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
        anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        anim.removedOnCompletion = YES;
        [layer addAnimation:anim forKey:kShrunkenTransformKey];
        
        self.alpha = 1;
    }
}

- (void)setIsSmallSize:(BOOL)isSmallSize;
{
    if (isSmallSize != _isSmallSize) {
        _isSmallSize = isSmallSize;
        if (isSmallSize) {
            [NSLayoutConstraint deactivateConstraints:@[self.metaDataBigHeight]];
            [NSLayoutConstraint activateConstraints:@[self.metaDataSmallHeight]];
        } else {
            [NSLayoutConstraint deactivateConstraints:@[self.metaDataSmallHeight]];
            [NSLayoutConstraint activateConstraints:@[self.metaDataBigHeight]];
        }
        self.metadataView.isSmallSize = isSmallSize;
    }
}

#pragma mark -
#pragma mark UIView subclass

- (void)willMoveToWindow:(UIWindow *)newWindow;
{
    NSArray *previewedItems = nil;

    if (newWindow && [(previewedItems = self.previewedItems) count] > 0) {
        [self loadPreviews];
    }
    [super willMoveToWindow:newWindow];
}

- (void)didMoveToWindow;
{
    if (!self.window) {
        [self discardCurrentPreviews];
    }
}

#ifdef OMNI_ASSERTIONS_ON
- (void)setNeedsLayout;
{
    OBPRECONDITION([NSThread isMainThread], "Sholdn't be laying out on a non-main thread! See <bug:///92753> for repro steps");
    [super setNeedsLayout];
}
#endif

- (void)layoutSubviews;
{
    OBPRECONDITION([NSThread isMainThread], "Sholdn't be laying out on a non-main thread! See <bug:///92753> for repro steps");
#if 0 && defined(DEBUG_kyle)
    // See <bug:///92753> (-[OUIDocumentPickerItemView layoutSubviews] called on background thread)
    if (![NSThread isMainThread])
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Sholdn't be laying out on a non-main thread! See <bug:///92753> for repro steps" userInfo:nil];
#endif
    
    OUIWithoutAnimating(^{
        CGRect bounds = self.bounds;
        
        _hairlineBorderView.frame = bounds;

        // Selection
        CGFloat thickness = [self _borderWidth];
        if (_selectionBorderView) {
            _selectionBorderView.frame = CGRectInset(bounds, thickness * -1, thickness * -1);
            _selectionBorderView.layer.borderWidth = thickness;
        }

        if (_statusImageView) {
            _statusImageView.contentMode = UIViewContentModeScaleAspectFit;

            UIImage *statusImage = _statusImageView.image;
            if (statusImage) {
                CGSize statusImageSize = statusImage.size;

                if (self.isSmallSize) {
                    // lets scale the badges by the same ratio that the actual thumbs are scaled
                    CGFloat decreaseFactor = kOUIDocumentPickerItemSmallSize / kOUIDocumentPickerItemNormalSize;
                    statusImageSize.height *= decreaseFactor;
                    statusImageSize.width *= decreaseFactor;
                }
            }
        }
        
    });
}

- (void)detachMetaDataView
{
    OUIDocumentPickerItemMetadataView *metaData = self.metadataView;
    CGRect frame = metaData.frame;
    frame = [metaData.superview convertRect:frame toView:self.superview];
    [metaData removeFromSuperview];
    metaData.translatesAutoresizingMaskIntoConstraints = YES;
    metaData.frame = frame;
    [self.superview addSubview:metaData];
    [NSLayoutConstraint deactivateConstraints:@[self.metaDataBigHeight, self.metaDataSmallHeight]];
}

- (void)reattachMetaDataView
{
    self.metadataView.translatesAutoresizingMaskIntoConstraints = NO;
    // and reset constraints
    [self insertSubview:self.metadataView aboveSubview:self.contentView];
    [self _nameChanged];
    [NSLayoutConstraint activateConstraints:[self constraintsToPositionMetaDataView]];
}

- (NSArray *)constraintsForBasicLayout
{
    if (!self.metaDataBigHeight) {
        // this constraint we create now to use if we need it, but don't return it in the array because we don't want it activated right now
        self.metaDataSmallHeight = [NSLayoutConstraint constraintWithItem:self.contentView
                                                                attribute:NSLayoutAttributeHeight
                                                                relatedBy:NSLayoutRelationEqual
                                                                   toItem:self.metadataView
                                                                attribute:NSLayoutAttributeHeight
                                                               multiplier:kOUIDocumentPickerMetaDataSmallSizeRatio
                                                                 constant:0];
        // this is the one we'll use right away
        self.metaDataBigHeight = [NSLayoutConstraint constraintWithItem:self.contentView
                                                              attribute:NSLayoutAttributeHeight
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:self.metadataView
                                                              attribute:NSLayoutAttributeHeight
                                                             multiplier:kOUIDocumentPickerMetaDataNormalSizeRatio
                                                               constant:0];
    }
    
    NSArray *constraints = @[
                             // content view all edges to superview
                             [self.contentView.topAnchor constraintEqualToAnchor:self.contentView.superview.topAnchor],
                             [self.contentView.rightAnchor constraintEqualToAnchor:self.contentView.superview.rightAnchor],
                             [self.contentView.bottomAnchor constraintEqualToAnchor:self.contentView.superview.bottomAnchor],
                             [self.contentView.leftAnchor constraintEqualToAnchor:self.contentView.superview.leftAnchor],
                             
                             [NSLayoutConstraint constraintWithItem:self.statusImageView
                                                          attribute:NSLayoutAttributeWidth
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.contentView
                                                          attribute:NSLayoutAttributeWidth
                                                         multiplier:0.20f
                                                           constant:0.0f],
                             [self.statusImageView.centerXAnchor constraintEqualToAnchor:self.contentView.rightAnchor],
                             [self.statusImageView.centerYAnchor constraintEqualToAnchor:self.contentView.topAnchor]
                             ];
    
    constraints = [constraints arrayByAddingObjectsFromArray:[self constraintsToPositionMetaDataView]];

    return constraints;
}

- (NSArray*)constraintsToPositionMetaDataView
{
    return @[
             // metadata view side and bottom edges to superview
             [self.metadataView.rightAnchor constraintEqualToAnchor:self.metadataView.superview.rightAnchor],
             [self.metadataView.bottomAnchor constraintEqualToAnchor:self.metadataView.superview.bottomAnchor],
             [self.metadataView.leftAnchor constraintEqualToAnchor:self.metadataView.superview.leftAnchor],
             ];
}

#pragma mark -
#pragma mark Internal

@synthesize metadataView = _metadataView;

- (void)itemChanged;
{
    // Don't keep the preview around unless the picker view wants us to display (or speculatively display) something.
    [self discardCurrentPreviews];

    [self _updateMetadataInteraction];
    [self _nameChanged];
    [self _selectedChanged];
    [self _dateChanged];
    [self _updateStatus];
    
    if (_item) {
        // We do NOT start a new preview load here if we aren't in the window, but delay that until we move into view. In some cases we want to make a file item view and manually give it a preview that we already have on hand. As long as we do that before it goes on screen we'll avoid a duplicate load.
        if (self.window)
            [self loadPreviews];
    }
}

- (void)prepareForReuse;
{
    [self setEditing:NO animated:NO];
    self.item = nil;
}

- (void)startRenaming;
{
    if (self.metadataView.superview != self.superview) {
        [self detachMetaDataView];
    }
    if ([_metadataView.nameTextField becomeFirstResponder]) {
        [_metadataView.nameTextField selectAll:nil];
    }
}

- (NSSet *)previewedItems;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)previewedItemsChanged;
{
    [self setNeedsLayout];
    [self loadPreviews];
}

- (void)loadPreviews;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_PREVIEW_DISPLAY(@"%s %p, item %@", __PRETTY_FUNCTION__, self, [_item shortDescription]);
    
    // Actually, we do need to be able to load previews when we don't have a view yet. In particular, if you are closing a document, we want its preview to start loading but it may never have been assigned a view (if the app launched with the document open and the doc picker has never been shown). We delay the display of the doc picker in this case until the preview has actually loaded.
#if 0
    if (!_view) {
        OBASSERT_NOT_REACHED("Don't ask for a preview if you aren't going to show it");
        return;
    }
#endif
    
    // Give our subclasses a chance to add and remove preview views.
    _deferLoadingPreviews = YES;
    [self layoutIfNeeded];
    _deferLoadingPreviews = NO;
    
    [self _loadOrDeferLoadingPreviewsForViewsStartingAtIndex:0];
}

- (void)_loadOrDeferLoadingPreviewsForViewsStartingAtIndex:(NSUInteger)index;
{
    if (!_deferLoadingPreviews) {
        NSArray *previewedItems = self.previewedItems;
        BOOL loadedAnyPreviews = NO;
        
        NSArray *previewViews = _contentView.sortedPreviewViews;
        for (NSUInteger i = index; i < previewViews.count; i++) {
            OBASSERT(i < previewViews.count);
            loadedAnyPreviews = [self _loadPreviewForPreviewView:previewViews[i] atIndex:i previewedItems:previewedItems] || loadedAnyPreviews;
        }
        
        if (loadedAnyPreviews)
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIDocumentPickerItemViewPreviewsDidLoadNotification object:self userInfo:nil];
    }
}

- (BOOL)_loadPreviewForPreviewView:(OUIDocumentPreviewView *)previewView atIndex:(NSUInteger)previewViewIndex previewedItems:(NSArray *)previewedItems;
{
    if (!previewedItems || previewViewIndex >= previewedItems.count) {
        DEBUG_PREVIEW_DISPLAY(@"  more preview views than we have previews");
        previewView.preview = nil;
        previewView.hidden = YES;
        return NO;
    }
    
    ODSItem *item = previewedItems[previewViewIndex];
    
    if ([item isKindOfClass:[ODSFolderItem class]]) {
        previewView.preview = nil;
        previewView.backgroundColor = self.backgroundColor;
        previewView.hidden = NO;
        return YES;
    } else {
        previewView.backgroundColor = nil;
    }
    
    ODSFileItem *fileItem = (ODSFileItem *)item;
    
    OUIDocumentPreview *candidatePreview = previewView.preview;
        
    if (candidatePreview.superseded)
        candidatePreview = nil;
    else if (OFNOTEQUAL(candidatePreview.fileURL, fileItem.fileURL)) {
        // The fileURL should contain the date and area of the preview.
        candidatePreview = nil;
    } else if (fileItem.isDownloaded && [candidatePreview.date compare:fileItem.fileModificationDate] == NSOrderedAscending) {
        // Keep using the old preview until the new version of a file is down downloading
        DEBUG_PREVIEW_DISPLAY(@"  new preview needed -- existing is older (was %@, now %@", candidatePreview.date, fileItem.fileModificationDate);
        candidatePreview = nil;
    }
    
    BOOL didLoadPreview;
    
    if (candidatePreview == nil) {
        DEBUG_PREVIEW_DISPLAY(@"  loading op for %@", [_item shortDescription]);
        
        Class documentClass = [[OUIDocumentAppController controller] documentClassForURL:fileItem.fileURL];
        OUIDocumentPreview *preview = [OUIDocumentPreview makePreviewForDocumentClass:documentClass fileItem:fileItem withArea:self.previewArea];
        
        // Don't explode if the preview fails to load and there is no default.
        if (preview)
            previewView.preview = preview;
        else
            OBASSERT_NOT_REACHED("Failed to generate a placeholder for file item %@; probably left with a stale preview", fileItem);
        
        didLoadPreview = YES;
    } else {
        DEBUG_PREVIEW_DISPLAY(@"  already had suitable preview %@", [candidatePreview shortDescription]);
        
        didLoadPreview = NO;
    }
    
    previewView.hidden = NO;
    return didLoadPreview;
}

- (void)discardCurrentPreviews;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    for (OUIDocumentPreviewView *previewView in _contentView.sortedPreviewViews)
        previewView.preview = nil;
}

- (void)previewsUpdated;
{
    // We want to keep displaying the old previews, but we *know* they are superseded and shouldn't be considered suitable.
    // In the case that a new document is appearing from iCloud/iTunes, the one second timestamp of the filesystem is not enough to ensure that our rewritten preview is considered newer than the placeholder that is initially generated. <bug:///75191> (Added a document to the iPad via iTunes File Sharing doesn't add a preview)
    for (OUIDocumentPreviewView *previewView in _contentView.sortedPreviewViews)
        previewView.preview.superseded = YES;

    if (self.window) {
        [self loadPreviews];
    }
}

- (NSArray *)loadedPreviews;
{
    return [_contentView.sortedPreviewViews arrayByPerformingSelector:@selector(preview)];
}

- (void)bounceDown;
{
    CALayer *layer = self.layer;
    
    CATransform3D xform = CATransform3DMakeScale(kOUIDocumentPreviewSelectionTouchBounceScale, kOUIDocumentPreviewSelectionTouchBounceScale, 1.0);
    
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform"];
    animation.fromValue = nil; // current value/identity?
    animation.toValue = [NSValue valueWithCATransform3D:xform];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    animation.duration = kOUIDocumentPreviewSelectionTouchBounceDuration;
    animation.autoreverses = YES;
    [layer addAnimation:animation forKey:@"bounceTransform"];
}

#pragma mark - NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &ItemContext) {
        if (OFISEQUAL(keyPath, ODSItemNameBinding))
            [self _nameChanged];
        else if (OFISEQUAL(keyPath, ODSItemSelectedBinding))
            [self _selectedChanged];
        else if (OFISEQUAL(keyPath, ODSItemUserModificationDateBinding))
            [self _dateChanged];
        else if (OFISEQUAL(keyPath, ODSItemIsDownloadedBinding) ||
                 OFISEQUAL(keyPath, ODSItemIsDownloadingBinding) ||
                 OFISEQUAL(keyPath, ODSItemIsUploadedBinding) ||
                 OFISEQUAL(keyPath, ODSItemIsUploadingBinding) ||
                 OFISEQUAL(keyPath, ODSItemPercentDownloadedBinding) ||
                 OFISEQUAL(keyPath, ODSItemPercentUploadedBinding)) {
            [self _updateStatus];
        }
        else
            OBASSERT_NOT_REACHED("Unknown KVO keyPath");
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - Accessibility
- (NSString *)accessibilityLabel;
{
    // so clients can use the setter to override the default label, if needed.
    NSString *label = [super accessibilityLabel];
    if (label) return label;
    
    // return the text field value so VO will speak the latest value regardless of editing state.
    
    return _metadataView.nameTextField.text;
}

- (NSString *)accessibilityValue
{
    if (_isEditingName) {
        return NSLocalizedStringFromTableInBundle(@"Is editing", @"OmniUIDocument", OMNI_BUNDLE, @"doc picker title label editing accessibility value");
    }
    
    ODSItem *fileItem = (ODSItem *)self.item;
    OBASSERT(!fileItem || [fileItem isKindOfClass:[ODSItem class]]);
    
    NSMutableArray *value = [[NSMutableArray alloc] init];
    
    // Badge Status
    NSString *badgeStatus = nil;
    if (fileItem.isDownloaded == NO) {
        badgeStatus = NSLocalizedStringFromTableInBundle(@"Not downloaded", @"OmniUIDocument", OMNI_BUNDLE, @"Not downloaded accessibility label.");
    }
    else if (fileItem.isUploaded == NO) {
        badgeStatus = NSLocalizedStringFromTableInBundle(@"Not uploaded", @"OmniUIDocument", OMNI_BUNDLE, @"Not uploaded accessibility label.");
    }
    
    if (badgeStatus) {
        [value addObjectIgnoringNil:badgeStatus];
    }
    
    // Modification Date
    NSString *displayDateString = [ODSItem displayStringForDate:fileItem.userModificationDate];
    // avoid reading the modification date on things without a date.
    if (displayDateString) {
        NSString *modifiedDate = NSLocalizedStringFromTableInBundle(@"Modified %@", @"OmniUIDocument", OMNI_BUNDLE, @"modified date accessibility value");
        modifiedDate = [NSString stringWithFormat:modifiedDate, displayDateString];
        [value addObjectIgnoringNil:modifiedDate];
    }
   
    return [value componentsJoinedByString:@", "];
}

- (UIAccessibilityTraits)accessibilityTraits;
{
    ODSItem *fileItem = (ODSItem *)self.item;
    OBASSERT(!fileItem || [fileItem isKindOfClass:[ODSItem class]]);
    
    if (fileItem.selected) {
        return UIAccessibilityTraitSelected;
    }
    
    return UIAccessibilityTraitNone;
}

- (NSArray *)accessibilityCustomActions
{
    // return the correct editing action based on the nameTextFields editing state.
    if (! _isEditingName) {
        return @[[self.cachedCustomAccessibilityActions firstObject]];
    }
    
    return @[[self.cachedCustomAccessibilityActions lastObject]];
}

- (void)_setupAccessibilityActions
{
    NSString *editNameString = NSLocalizedStringFromTableInBundle(@"Edit name", @"OmniUIDocument", OMNI_BUNDLE, @"doc picker custom accessibility action name");
    UIAccessibilityCustomAction *editName = [[UIAccessibilityCustomAction alloc] initWithName:editNameString target:self selector:@selector(_accessibilityHandleNameEditAction:)];
    
    NSString *clearNameString = NSLocalizedStringFromTableInBundle(@"Clear name field", @"OmniUIDocument", OMNI_BUNDLE, @"doc picker custom accessibility action name");
    UIAccessibilityCustomAction *clearName = [[UIAccessibilityCustomAction alloc] initWithName:clearNameString target:self selector:@selector(_accessibilityHandleNameEditAction:)];
    
    _cachedCustomAccessibilityActions = @[editName, clearName];
}

- (BOOL)_accessibilityHandleNameEditAction:(UIAccessibilityCustomAction *)action;
{
    if (! _isEditingName) {
        [self startRenaming];
    } else {
        _metadataView.nameTextField.text = nil;
    }
    
    return YES;
}

#pragma mark - UIDragInteractionDelegate

- (NSArray<UIDragItem *> *)_itemsForDragSession:(id<UIDragSession>)session;
{
    ODSItem *item = self.item;
    if (![item isKindOfClass:[ODSFileItem class]])
        return @[];
    ODSFileItem *fileItem = (ODSFileItem *)item;

    NSItemProvider *itemProvider = [[NSItemProvider alloc] init];
    itemProvider.suggestedName = fileItem.name;
    [itemProvider registerFileRepresentationForTypeIdentifier:fileItem.fileType fileOptions:NSItemProviderFileOptionOpenInPlace visibility:NSItemProviderRepresentationVisibilityAll loadHandler:^NSProgress * _Nullable(void (^ _Nonnull completionHandler)(NSURL * _Nullable, BOOL, NSError * _Nullable)) {
        completionHandler(fileItem.fileURL, YES, nil);
        return nil;
    }];

    UIDragItem *dragItem = [[UIDragItem alloc] initWithItemProvider:itemProvider];
    dragItem.localObject = item;
    return @[dragItem];
}

- (NSArray<UIDragItem *> *)dragInteraction:(UIDragInteraction *)interaction itemsForBeginningSession:(id<UIDragSession>)session;
{
    return [self _itemsForDragSession:session];
}

- (NSArray<UIDragItem *> *)dragInteraction:(UIDragInteraction *)interaction itemsForAddingToSession:(id<UIDragSession>)session withTouchAtPoint:(CGPoint)point;
{
    return [self _itemsForDragSession:session];
}

#pragma mark - Private

- (void)_updateRasterizesLayer;
{
    // Turn off rasterization while editing ... later we'll probably want to turn it off when we have a progress bar too.
    BOOL shouldRasterize = (_isEditingName == NO);
    
    self.layer.shouldRasterize = shouldRasterize;
    self.layer.rasterizationScale = [[UIScreen mainScreen] scale];
}

- (void)_nameTextFieldEditingDidBegin:(id)sender;
{
    OBPRECONDITION(_isEditingName == NO);
    _isEditingName = YES;
    [self _updateRasterizesLayer];

    _metadataView.showsImage = NO;
    
    [UIView performWithoutAnimation:^{
        [_metadataView setNeedsLayout];
        [_metadataView layoutIfNeeded];
    }];
    
    self.hackyTimerToGetRenamingToWorkWithProKeyboard = [NSTimer timerWithTimeInterval:0.1
                                                                                target:self
                                                                              selector:@selector(hackyTimerForProKeyboardFired)
                                                                              userInfo:nil
                                                                               repeats:NO];
    
    [[NSRunLoop mainRunLoop] addTimer:self.hackyTimerToGetRenamingToWorkWithProKeyboard forMode:NSRunLoopCommonModes];
    
}

- (void)hackyTimerForProKeyboardFired
{
    // the keyboard hasn't yet started to appear, so we're going to assume it won't appear at all and we'd better do the animation now.
    // this is necessary because when there is an onscreen keyboard, we want to animate alongside its appearance.  but we don't want to fail to perform the animation if no onscreen keyboard will appear.  And the keyboardWillShow message comes through after the didBeginEditing message, so we can't just start the animation from didBeginEditing.
    [self _keyboardWillShow];
}

- (void)_keyboardWillShow
{
    if (_isEditingName) {
        [self.hackyTimerToGetRenamingToWorkWithProKeyboard invalidate];
        self.hackyTimerToGetRenamingToWorkWithProKeyboard = nil;
        id target = [self targetForAction:@selector(documentPickerItemNameStartedEditing:) withSender:self];
        OBASSERT(target);
        [target documentPickerItemNameStartedEditing:self];
    }
}

- (void)_nameTextFieldEndedEditing:(id)sender;
{
    OBPRECONDITION(_isEditingName == YES);
    _isEditingName = NO;
    [self _updateRasterizesLayer];
    
    _metadataView.showsImage = YES;
    
    [UIView performWithoutAnimation:^{
        [_metadataView setNeedsLayout];
        [_metadataView layoutIfNeeded];
    }];

    id target = [self targetForAction:@selector(documentPickerItemNameEndedEditing:withName:) withSender:self];
    OBASSERT(target);
    [target documentPickerItemNameEndedEditing:self withName:_metadataView.nameTextField.text];
}

- (void)_nameChanged;
{
    NSString *name = [_item name];
    if (!name)
        name = @"";
    
    _metadataView.name = name;
    
    [self setNeedsLayout];
}

- (void)_selectedChanged;
{
    BOOL selected = _item.selected;
    if (_selected == selected)
        return;
    
    _selected = selected;
    
    if (_selected && !_selectionBorderView) {
        OUIWithoutAnimating(^{
            _selectionBorderView = [[UIView alloc] init];
            _selectionBorderView.userInteractionEnabled = NO;
            _selectionBorderView.layer.borderColor = [[OAMakeColor(kOUIDocumentPreviewViewSelectedBorderColor) toColor] CGColor];
            _selectionBorderView.layer.borderWidth = [self _borderWidth];
            [self insertSubview:_selectionBorderView belowSubview:_hairlineBorderView];
        });
    } else if (!_selected && _selectionBorderView) {
        [_selectionBorderView removeFromSuperview];
        _selectionBorderView = nil;
    }
    
    [self setNeedsLayout];
}

- (void)_dateChanged;
{
    if (self.isReadOnly) {
        _metadataView.dateString = @"";
        return;
    }

    NSDate *date = [_item userModificationDate];

    NSString *dateString;
    if (date) {
        if (CGRectGetWidth(self.frame) < 200.0) {
            static NSDateFormatter *formatter = nil;
            
            if (!formatter) {
                formatter = [[NSDateFormatter alloc] init];
                formatter.dateStyle = NSDateFormatterLongStyle;
                formatter.timeStyle = NSDateFormatterNoStyle;
            }
            dateString = [formatter stringFromDate:date];
        } else
            dateString = [[_item class] displayStringForDate:date];
    } else
        dateString = @"";
        
    _metadataView.dateString = dateString;
    
    [self setNeedsLayout];
}

- (void)_updateStatus;
{
    UIImage *statusImage = nil;
    if (_item.isDownloaded == NO) {
        statusImage = [UIImage imageNamed:@"OUIDocumentStatusNotDownloaded" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
        OBASSERT(statusImage);
    } else if (_item.isUploaded == NO) {
        statusImage = [UIImage imageNamed:@"OUIDocumentStatusNotUploaded" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
        OBASSERT(statusImage);
    } else if (_item.scope.isExternal) {
        statusImage = [UIImage imageNamed:@"OUIDocumentStatusLinked" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    }
    self.statusImage = statusImage;
    
    BOOL showProgress = NO;
    double percent = 0;
    
    if (_item.isDownloading) {
        percent = _item.percentDownloaded;
    } else if (_item.isUploading) {
        percent = _item.percentUploaded;
    }
    
    showProgress = (percent > 0) && (percent < 1);
    
    self.showsProgress = showProgress;
    self.progress = percent;
}

- (void)_updateMetadataInteraction;
{
    if (self.isReadOnly || !_item.isValid || _item.scope == nil || ![_item.scope canRenameDocuments]) {
        _metadataView.userInteractionEnabled = NO;
        return;
    }

    // We don't want to allow renaming in the case that our container is in Edit mode (selecting files and folders).
    _metadataView.userInteractionEnabled = !_containerIsSelecting;
}

- (CGFloat)_borderWidth;
{
    CGFloat width = self.isSmallSize ? kOUIDocumentPreviewViewSmallSelectedBorderThickness : kOUIDocumentPreviewViewSelectedBorderThickness;
    if (self.metadataView.doubleSizeFonts) {
        width *= 2;
    }
    return width;
}

@end
