// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentPickerItemView.h>

#import <OmniUI/OUIDocumentPreviewView.h>
#import <OmniUI/OUIDocumentPreview.h>
#import <OmniUI/OUISingleDocumentAppController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>

#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIParameters.h"
#import "OUIFeatures.h"

RCS_ID("$Id$");

NSString * const OUIDocumentPickerItemViewPreviewsDidLoadNotification = @"OUIDocumentPickerItemViewPreviewsDidLoadNotification";

@interface OUIDocumentPickerItemView ()
- (void)_nameChanged;
- (void)_dateChanged;
- (void)_updateStatus;
@end

@implementation OUIDocumentPickerItemView
{
    BOOL _animatingRotationChange;
    BOOL _landscape;
    OFSDocumentStoreItem *_item;
    UILabel *_nameLabel;
    UILabel *_dateLabel;
    
    OUIDocumentPreviewView *_previewView;

    OUIDocumentPickerItemViewDraggingState _draggingState;
    
    BOOL _highlighted;
    BOOL _renaming;
    BOOL _deleting;
}

static void _configureLabel(UILabel *label, CGFloat fontSize)
{
    label.shadowColor = [UIColor colorWithWhite:kOUIDocumentPickerItemViewLabelShadowWhiteAlpha.w alpha:kOUIDocumentPickerItemViewLabelShadowWhiteAlpha.a];
    label.shadowOffset = CGSizeMake(0, 1);
    label.backgroundColor = nil;
    label.opaque = NO;
    label.textAlignment = UITextAlignmentCenter;
    label.font = [UIFont boldSystemFontOfSize:fontSize];
    label.numberOfLines = 1;
}

static id _commonInit(OUIDocumentPickerItemView *self)
{
    self->_nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _configureLabel(self->_nameLabel, kOUIDocumentPickerItemViewNameLabelFontSize);
    self->_nameLabel.textColor = [UIColor colorWithWhite:kOUIDocumentPickerItemViewNameLabelWhiteAlpha.w alpha:kOUIDocumentPickerItemViewNameLabelWhiteAlpha.a];
    
    self->_dateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _configureLabel(self->_dateLabel, kOUIDocumentPickerItemViewDetailLabelFontSize);
    self->_dateLabel.textColor = [UIColor colorWithWhite:kOUIDocumentPickerItemViewDetailLabelWhiteAlpha.w alpha:kOUIDocumentPickerItemViewDetailLabelWhiteAlpha.a];
    
    self->_previewView = [[OUIDocumentPreviewView alloc] initWithFrame:CGRectZero];
    
    [self addSubview:self->_previewView];
    [self addSubview:self->_nameLabel];
    [self addSubview:self->_dateLabel];
    
//    self.layer.borderColor = [[UIColor blueColor] CGColor];
//    self.layer.borderWidth = 1;
    
    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    if (!(self = [super initWithCoder:aDecoder]))
        return nil;
    return _commonInit(self);
}

- (void)dealloc;
{
    [self stopObservingItem:_item];
    
    [_item release];
    [_nameLabel release];
    [_dateLabel release];
    [_previewView release];
    
    [super dealloc];
}

@synthesize landscape = _landscape;
- (void)setLandscape:(BOOL)landscape;
{
    OBPRECONDITION(_item == nil); // Set this up first
    _landscape = landscape;
    _previewView.landscape = landscape;
}

@synthesize animatingRotationChange = _animatingRotationChange;

@synthesize item = _item;
- (void)setItem:(id)item;
{
    if (_item == item)
        return;
    
    if (_item)
        [self stopObservingItem:_item];
    
    [_item release];
    _item = [item retain];
    
    if (_item)
        [self startObservingItem:_item];
    
    [self itemChanged];
}

static unsigned ItemContext;

- (void)startObservingItem:(id)item;
{
    [item addObserver:self forKeyPath:OFSDocumentStoreItemNameBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OFSDocumentStoreItemDateBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OFSDocumentStoreItemReadyBinding options:0 context:&ItemContext];
    
    [item addObserver:self forKeyPath:OFSDocumentStoreItemHasUnresolvedConflictsBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OFSDocumentStoreItemIsDownloadedBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OFSDocumentStoreItemIsDownloadingBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OFSDocumentStoreItemIsUploadedBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OFSDocumentStoreItemIsUploadingBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OFSDocumentStoreItemPercentDownloadedBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OFSDocumentStoreItemPercentUploadedBinding options:0 context:&ItemContext];
}

- (void)stopObservingItem:(id)item;
{
    [item removeObserver:self forKeyPath:OFSDocumentStoreItemNameBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OFSDocumentStoreItemDateBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OFSDocumentStoreItemReadyBinding context:&ItemContext];

    [item removeObserver:self forKeyPath:OFSDocumentStoreItemHasUnresolvedConflictsBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OFSDocumentStoreItemIsDownloadedBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OFSDocumentStoreItemIsDownloadingBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OFSDocumentStoreItemIsUploadedBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OFSDocumentStoreItemIsUploadingBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OFSDocumentStoreItemPercentDownloadedBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OFSDocumentStoreItemPercentUploadedBinding context:&ItemContext];
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
    _previewView.highlighted = highlighted;
}

@synthesize renaming = _renaming;
- (void)setRenaming:(BOOL)renaming;
{
    if (_renaming == renaming)
        return;
    _renaming = renaming;
    
    [self setNeedsLayout];
}

static NSString * const EditingAnimationKey = @"editingAnimation";

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
{
    // Since our files can't be picked up yet (grouping support not ready), don't make them look wiggly.
#if OUI_DOCUMENT_GROUPING
    // iWork jittes the entire item. I find it hard to read the text. Also the jitter is too scary and we'd like a more gentle animation
    CALayer *layer = _previewView.layer;
    
    if (!editing) {
        // TODO: Slowly lower the layer back
        [layer removeAnimationForKey:EditingAnimationKey];
    } else {
        
        //        CABasicAnimation *boundsAnimation = [CABasicAnimation animationWithKeyPath:@"bounds"];
        //        boundsAnimation.fromValue = [NSValue valueWithCGRect:layer.bounds];
        //        boundsAnimation.toValue = [NSValue valueWithCGRect:CGRectInset(layer.bounds, -6, -6)];
        //        boundsAnimation.autoreverses = YES;
        //        boundsAnimation.duration = 1.0;
        //        boundsAnimation.timeOffset = OFRandomNextDouble();
        //        boundsAnimation.repeatCount = FLT_MAX;
        
        
        CGFloat angle = 1.5 * (M_PI/180);
        CABasicAnimation *jitter = [CABasicAnimation animationWithKeyPath:@"transform"];
        jitter.fromValue = [NSValue valueWithCATransform3D:CATransform3DMakeRotation(-angle, 0, 0, 1)];
        jitter.toValue = [NSValue valueWithCATransform3D:CATransform3DMakeRotation(angle, 0, 0, 1)];
        jitter.autoreverses = YES;
        jitter.duration = 0.125;
        jitter.timeOffset = OFRandomNextDouble();
        jitter.repeatCount = FLT_MAX; // needed?
        
        //CAAnimationGroup *group = [CAAnimationGroup animation];
        //group.animations = [NSArray arrayWithObjects:jitter, nil];
        //group.duration = DBL_MAX;
        
        //[layer addAnimation:group forKey:EditingAnimationKey];
        [layer addAnimation:jitter forKey:EditingAnimationKey];
    }
    
    _previewView.needsAntialiasingBorder = editing;
#endif
}

@synthesize shrunken = _shrunken;
- (void)setShrunken:(BOOL)shrunken;
{
    if (_shrunken == shrunken)
        return;
    
    _shrunken = shrunken;

    static NSString * const kShrunkenTransformKey = @"shrunkenTransform";

    CALayer *layer = self.layer;
    if (!_shrunken && [UIView areAnimationsEnabled] == NO) {
        [layer removeAnimationForKey:kShrunkenTransformKey];
        self.alpha = 1;
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

#pragma mark -
#pragma mark UIView subclass

- (void)willMoveToWindow:(UIWindow *)newWindow;
{
    NSSet *previewedFileItems = nil;

    if (newWindow && [(previewedFileItems = self.previewedFileItems) count] > 0) {
        [self loadPreviews];
    } else {
        [self discardCurrentPreviews];
    }
    
    [super willMoveToWindow:newWindow];
}

- (void)layoutSubviews;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // Newly appearing item views shouldn't animate their guts.
    // Sadly there is no good place to put this on the normal rotation path (after the rotation has started AND the top view frame has been changed, but before the rotation has finished).
    OUIWithAnimationsDisabled(_animatingRotationChange, ^{
        
        CGRect bounds = self.bounds;
        
        CGRect previewFrame = bounds;
        
        {
            CGSize dateSize = [_dateLabel sizeThatFits:bounds.size];
            dateSize.height = floor(dateSize.height);
            
            previewFrame.size.height -= dateSize.height;
            _dateLabel.frame = CGRectMake(CGRectGetMinX(previewFrame), CGRectGetMaxY(previewFrame),
                                          CGRectGetWidth(previewFrame), dateSize.height);
        }
        
        previewFrame.size.height -= kOUIDocumentPickerItemViewNameToDatePadding;
        
        {
            CGSize nameSize = [_nameLabel sizeThatFits:bounds.size];
            nameSize.height = floor(nameSize.height);
            
            previewFrame.size.height -= nameSize.height;
            _nameLabel.frame = CGRectMake(CGRectGetMinX(previewFrame), CGRectGetMaxY(previewFrame),
                                          CGRectGetWidth(previewFrame), nameSize.height);
        }
        
        previewFrame.size.height -= kOUIDocumentPickerItemViewNameToPreviewPadding;
        
        BOOL draggingSource = (_draggingState == OUIDocumentPickerItemViewSourceDraggingState);
        _nameLabel.hidden = draggingSource;
        _dateLabel.hidden = draggingSource;
        _previewView.draggingSource = draggingSource;
        
        previewFrame = [_previewView previewRectInFrame:previewFrame];
        if (CGRectEqualToRect(previewFrame, CGRectNull)) {
            _previewView.hidden = YES;
        } else {
            _previewView.frame = previewFrame;
            
            if (_renaming)
                _previewView.hidden = YES;
            else
                _previewView.hidden = NO;
        }
    });
}

#pragma mark -
#pragma mark Internal

@synthesize previewView = _previewView;

- (void)itemChanged;
{
    // Don't keep the preview around unless the picker view wants us to display (or speculatively display) something.
    [self discardCurrentPreviews];

    [self _nameChanged];
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

- (NSSet *)previewedFileItems;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)previewedFileItemsChanged;
{
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
    
    NSSet *previewedFileItems = self.previewedFileItems;
    if ([previewedFileItems count] == 0) {
        DEBUG_PREVIEW_DISPLAY(@"  bail -- no previews desired");
        return;
    }
    
    if (!_item.ready) {
        DEBUG_PREVIEW_DISPLAY(@"  bail -- item isn't ready");
        return;
    }
    
    NSArray *existingPreviews = _previewView.previews;
    
    OBFinishPortingLater("If we get called twice before previews finish loading, we'll load them twice. Would be nice to check our running operations too.");
    
    NSMutableArray *loadedPreviews = nil;
    
    for (OFSDocumentStoreFileItem *fileItem in previewedFileItems) {
        OBASSERT([fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);
        
        OUIDocumentPreview *suitablePreview = [existingPreviews first:^(id obj){
            OUIDocumentPreview *preview = obj;
            
            if (preview.superseded)
                return NO;
            
            // The fileURL should contain the date and landscape-ness of the preview.
            if (OFNOTEQUAL(preview.fileURL, fileItem.fileURL))
                return NO;
            
            // Keep using the old preview until the new version of a file is down downloading
            if (fileItem.isDownloaded && [preview.date compare:fileItem.date] == NSOrderedAscending) {
                DEBUG_PREVIEW_DISPLAY(@"  new preview needed -- existing is older (was %@, now %@", preview.date, [fileItem date]);
                return NO;
            }
            return YES;
        }];
        
        if (suitablePreview == nil) {
            DEBUG_PREVIEW_DISPLAY(@"  loading op for %@", [_item shortDescription]);
            
            Class documentClass = [[OUISingleDocumentAppController controller] documentClassForURL:fileItem.fileURL];

            if (!loadedPreviews)
                loadedPreviews = [NSMutableArray array];
            OUIDocumentPreview *preview = [OUIDocumentPreview makePreviewForDocumentClass:documentClass fileURL:fileItem.fileURL date:fileItem.date withLandscape:_landscape];
            
            // Don't explode if the preview fails to load and there is no default.
            if (preview)
                [loadedPreviews addObject:preview];
        } else {
            DEBUG_PREVIEW_DISPLAY(@"  already had suitable preview %@", [suitablePreview shortDescription]);
        }
    }
    
    if (loadedPreviews) {
        BOOL disableLayerAnimations = ![UIView areAnimationsEnabled] || (self.window == nil);
        OUIWithLayerAnimationsDisabled(disableLayerAnimations, ^{
            if (!disableLayerAnimations) {
                [CATransaction begin];
                [CATransaction setAnimationDuration:0.33];
            }
            
            for (OUIDocumentPreview *preview in loadedPreviews) {
                DEBUG_PREVIEW_DISPLAY(@"%s add preview:%@ view:%p current size:%@", __PRETTY_FUNCTION__, [preview shortDescription], self, NSStringFromCGSize(self.frame.size));
                [_previewView addPreview:preview];
            }
            [_previewView layoutIfNeeded];
            
            if (!disableLayerAnimations) {
                [CATransaction commit];
            }
        });
        
        [[NSNotificationCenter defaultCenter] postNotificationName:OUIDocumentPickerItemViewPreviewsDidLoadNotification object:self userInfo:nil];
    }
}

- (void)discardCurrentPreviews;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    [_previewView discardPreviews];
}

- (void)previewsUpdated;
{
    // We want to keep displaying the old previews, but we *know* they are superseded and shouldn't be considered suitable.
    // In the case that a new document is appearing from iCloud/iTunes, the one second timestamp of the filesystem is not enough to ensure that our rewritten preview is considered newer than the placeholder that is initially generated. <bug:///75191> (Added a document to the iPad via iTunes File Sharing doesn't add a preview)
    for (OUIDocumentPreview *preview in _previewView.previews)
        preview.superseded = YES;
    
    [self loadPreviews];
}

- (NSArray *)loadedPreviews;
{
    return [NSArray arrayWithArray:_previewView.previews];
}

- (OUIDocumentPreview *)currentPreview;
{
    NSArray *previews = _previewView.previews;
    OBASSERT([previews count] <= 1);
    return [previews lastObject];
}

#pragma mark -
#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &ItemContext) {
        if (OFISEQUAL(keyPath, OFSDocumentStoreItemNameBinding))
            [self _nameChanged];
        else if (OFISEQUAL(keyPath, OFSDocumentStoreItemDateBinding))
            [self _dateChanged];
        else if (OFISEQUAL(keyPath, OFSDocumentStoreItemReadyBinding)) {
            if (self.window)
                [self loadPreviews];
        } else if (OFISEQUAL(keyPath, OFSDocumentStoreItemHasUnresolvedConflictsBinding) ||
                 OFISEQUAL(keyPath, OFSDocumentStoreItemIsDownloadedBinding) ||
                 OFISEQUAL(keyPath, OFSDocumentStoreItemIsDownloadingBinding) ||
                 OFISEQUAL(keyPath, OFSDocumentStoreItemIsUploadedBinding) ||
                 OFISEQUAL(keyPath, OFSDocumentStoreItemIsUploadingBinding) ||
                 OFISEQUAL(keyPath, OFSDocumentStoreItemPercentDownloadedBinding) ||
                 OFISEQUAL(keyPath, OFSDocumentStoreItemPercentUploadedBinding)) {
            [self _updateStatus];
        }
        else
            OBASSERT_NOT_REACHED("Unknown KVO keyPath");
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark -
#pragma mark Private

- (void)_nameChanged;
{
    NSString *name = [_item name];
    if (!name)
        name = @"";
    
    _nameLabel.text = name;
    
    [self setNeedsLayout];
}

- (void)_dateChanged;
{
    NSDate *date = [_item date];

    NSString *dateString;
    if (date)
        dateString = [[_item class] displayStringForDate:date];
    else
        dateString = @"";
        
    _dateLabel.text = dateString;
    
    [self setNeedsLayout];
}

- (void)_updateStatus;
{
    UIImage *statusImage = nil;
    if (_item.hasUnresolvedConflicts) {
        statusImage = [UIImage imageNamed:@"OUIDocumentStatusConflictingVersions.png"];
        OBASSERT(statusImage);
    } else if (_item.isDownloaded == NO) {
        statusImage = [UIImage imageNamed:@"OUIDocumentStatusNotDownloaded.png"];
        OBASSERT(statusImage);
    } else if (_item.isUploaded == NO) {
        statusImage = [UIImage imageNamed:@"OUIDocumentStatusNotUploaded.png"];
        OBASSERT(statusImage);
    }
    _previewView.statusImage = statusImage;
    
    BOOL showProgress = NO;
    double percent = 0;
    
    if (_item.isDownloading) {
        showProgress = YES;
        percent = _item.percentDownloaded;
    } else if (_item.isUploading) {
        showProgress = YES;
        percent = _item.percentUploaded;
    } else {
        showProgress = NO;
    }
    
    _previewView.downloading = _item.isDownloading;
    _previewView.showsProgress = showProgress;
    _previewView.progress = percent / 100;
}

@end
