// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentPickerItemView.h>

#import <OmniUI/OUIDocumentPreviewView.h>
#import <OmniUI/OUIDocumentPreview.h>
#import <OmniUI/OUIDocumentStoreFileItem.h>
#import <OmniUI/OUISingleDocumentAppController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniFoundation/OFRandom.h>

#import "OUIDocumentStore-Internal.h"
#import "OUIDocumentStoreItem-Internal.h"
#import "OUIDocumentStoreFileItem-Internal.h"
#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIDocumentPreviewLoadOperation.h"
#import "OUIParameters.h"

RCS_ID("$Id$");

static NSOperationQueue *PreviewLoadOperationQueue = nil;

NSString * const OUIDocumentPickerItemViewPreviewsDidLoadNotification = @"OUIDocumentPickerItemViewPreviewsDidLoadNotification";

@interface OUIDocumentPickerItemView ()
- (void)_nameChanged;
- (void)_dateChanged;
- (void)_updateStatus;
@end

@implementation OUIDocumentPickerItemView
{
    BOOL _landscape;
    OUIDocumentStoreItem *_item;
    UILabel *_nameLabel;
    UILabel *_dateLabel;
    
    OUIDocumentPreviewView *_previewView;
    NSMutableArray *_previewLoadOperations;

    OUIDocumentPickerItemViewDraggingState _draggingState;
    
    BOOL _renaming;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    PreviewLoadOperationQueue = [[NSOperationQueue alloc] init];
    PreviewLoadOperationQueue.name = @"OUIDocumentPicker preview loading";
    // Our previews are fairly small now; allow loading multiples on multicore devices.
    //[PreviewLoadOperationQueue setMaxConcurrentOperationCount:1];
};

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
    for (OUIDocumentPreviewLoadOperation *operation in _previewLoadOperations)
        [operation cancel];
    [_previewLoadOperations release];
    
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
}

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
    [item addObserver:self forKeyPath:OUIDocumentStoreItemNameBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OUIDocumentStoreItemDateBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OUIDocumentStoreItemReadyBinding options:0 context:&ItemContext];
    
    [item addObserver:self forKeyPath:OUIDocumentStoreItemHasUnresolvedConflictsBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OUIDocumentStoreItemIsDownloadedBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OUIDocumentStoreItemIsDownloadingBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OUIDocumentStoreItemIsUploadedBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OUIDocumentStoreItemIsUploadingBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OUIDocumentStoreItemPercentDownloadedBinding options:0 context:&ItemContext];
    [item addObserver:self forKeyPath:OUIDocumentStoreItemPercentUploadedBinding options:0 context:&ItemContext];
}

- (void)stopObservingItem:(id)item;
{
    [item removeObserver:self forKeyPath:OUIDocumentStoreItemNameBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OUIDocumentStoreItemDateBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OUIDocumentStoreItemReadyBinding context:&ItemContext];

    [item removeObserver:self forKeyPath:OUIDocumentStoreItemHasUnresolvedConflictsBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OUIDocumentStoreItemIsDownloadedBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OUIDocumentStoreItemIsDownloadingBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OUIDocumentStoreItemIsUploadedBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OUIDocumentStoreItemIsUploadingBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OUIDocumentStoreItemPercentDownloadedBinding context:&ItemContext];
    [item removeObserver:self forKeyPath:OUIDocumentStoreItemPercentUploadedBinding context:&ItemContext];
}

- (BOOL)isLoadingPreviews;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // We don't know what previews to load until we are ready, so just claim to be loading until we are ready.
    if (!_item.ready)
        return YES;
        
    return [_previewLoadOperations count] > 0;
}

@synthesize draggingState = _draggingState;
- (void)setDraggingState:(OUIDocumentPickerItemViewDraggingState)draggingState;
{
    if (_draggingState == draggingState)
        return;
    
    _draggingState = draggingState;
    [self setNeedsLayout];
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
}

#pragma mark -
#pragma mark UIView subclass

- (void)willMoveToWindow:(UIWindow *)newWindow;
{
    NSSet *previewedFileItems = nil;

    if (newWindow && [(previewedFileItems = self.previewedFileItems) count] > 0) {
        if (!self.loadingPreviews)
            [self startLoadingPreviews];
    } else {
        [self stopLoadingPreviewsAndDiscardCurrentPreviews:YES];
    }
    
    [super willMoveToWindow:newWindow];
}

- (void)layoutSubviews;
{
    OBPRECONDITION([NSThread isMainThread]);
    
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
}

#pragma mark -
#pragma mark Internal

@synthesize previewView = _previewView;

- (void)itemChanged;
{
    // Don't keep the preview around unless the picker view wants us to display (or speculatively display) something.
    [self stopLoadingPreviewsAndDiscardCurrentPreviews:YES];

    [self _nameChanged];
    [self _dateChanged];
    [self _updateStatus];
    
    if (_item) {
        // We do NOT start a new preview load here if we aren't in the window, but delay that until we move into view. In some cases we want to make a file item view and manually give it a preview that we already have on hand. As long as we do that before it goes on screen we'll avoid a duplicate load.
        if (self.window)
            [self startLoadingPreviews];
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
    [self stopLoadingPreviewsAndDiscardCurrentPreviews:NO];
    [self startLoadingPreviews];
}

- (void)startLoadingPreviews;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_previewLoadOperations == nil); // should stop loading previews before restarting, or we can get duplicate operations
    
    PREVIEW_DEBUG(@"%s %p, item %@", __PRETTY_FUNCTION__, self, [_item shortDescription]);
    
    // Actually, we do need to be able to load previews when we don't have a view yet. In particular, if you are closing a document, we want its preview to start loading but it may never have been assigned a view (if the app launched with the document open and the doc picker has never been shown). We delay the display of the doc picker in this case until the preview has actually loaded.
#if 0
    if (!_view) {
        OBASSERT_NOT_REACHED("Don't ask for a preview if you aren't going to show it");
        return;
    }
#endif
    
    NSSet *previewedFileItems = self.previewedFileItems;
    if ([previewedFileItems count] == 0) {
        PREVIEW_DEBUG(@"  bail -- no previews desired");
        return;
    }
    
    if (!_item.ready) {
        PREVIEW_DEBUG(@"  bail -- item isn't ready");
        return;
    }
    
    NSArray *existingPreviews = _previewView.previews;
    
    OBFinishPortingLater("If we get called twice before previews finish loading, we'll load them twice. Would be nice to check our running operations too.");
    
    for (OUIDocumentStoreFileItem *fileItem in previewedFileItems) {
        OBASSERT([fileItem isKindOfClass:[OUIDocumentStoreFileItem class]]);
        
        OUIDocumentPreview *suitablePreview = [existingPreviews first:^(id obj){
            OUIDocumentPreview *preview = obj;
            
            if (preview.superseded)
                return NO;
            
            if (preview.fileItem != fileItem)
                return NO;
            
            if (preview.landscape ^ _landscape) {
                PREVIEW_DEBUG(@"  new preview needed -- existing is wrong orientation (wanted %s)", _landscape ? "landscape" : "portrait");
                return NO;
            }
            
            // Keep using the old preview until the new version of a file is down downloading
            if (fileItem.isDownloaded && [preview.date compare:fileItem.date] == NSOrderedAscending) {
                PREVIEW_DEBUG(@"  new preview needed -- existing is older (was %@, now %@", preview.date, [fileItem date]);
                return NO;
            }
            return YES;
        }];
        
        if (suitablePreview == nil) {
            PREVIEW_DEBUG(@"  starting op for %@", [_item shortDescription]);
            
            // Load the preview in the background.
            if (!_previewLoadOperations)
                _previewLoadOperations = [[NSMutableArray alloc] init];
            
            Class documentClass = [[OUISingleDocumentAppController controller] documentClassForURL:fileItem.fileURL];
            
            OUIDocumentPreviewLoadOperation *operation = [[OUIDocumentPreviewLoadOperation alloc] initWithView:self documentClass:documentClass fileItem:fileItem landscape:_landscape];
            [operation setQueuePriority:NSOperationQueuePriorityLow];
            
            [_previewLoadOperations addObject:operation];
            [PreviewLoadOperationQueue addOperation:operation];
            [operation release];
        } else {
            PREVIEW_DEBUG(@"  already had suitable preview %@", [suitablePreview shortDescription]);
        }
    }
}

- (void)stopLoadingPreviewsAndDiscardCurrentPreviews:(BOOL)discardPreviews;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_previewLoadOperations) {
        PREVIEW_DEBUG(@"%s", __PRETTY_FUNCTION__);
    
        for (OUIDocumentPreviewLoadOperation *operation in _previewLoadOperations)
            [operation cancel];
        [_previewLoadOperations release];
        _previewLoadOperations = nil;
    }
    
    if (discardPreviews)
        [_previewView discardPreviews];
}

- (void)previewsUpdated;
{
    // We want to keep displaying the old previews, but we *know* they are superseded and shouldn't be considered suitable.
    // In the case that a new document is appearing from iCloud/iTunes, the one second timestamp of the filesystem is not enough to ensure that our rewritten preview is considered newer than the placeholder that is initially generated. <bug:///75191> (Added a document to the iPad via iTunes File Sharing doesn't add a preview)
    for (OUIDocumentPreview *preview in _previewView.previews)
        preview.superseded = YES;
    
    [self stopLoadingPreviewsAndDiscardCurrentPreviews:NO];
    [self startLoadingPreviews];
}

- (OUIDocumentPreview *)currentPreview;
{
    NSArray *previews = _previewView.previews;
    OBASSERT([previews count] <= 1);
    return [previews lastObject];
}

- (void)previewLoadOperation:(OUIDocumentPreviewLoadOperation *)operation loadedPreview:(OUIDocumentPreview *)preview;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(preview); // should be a default, at least
    
    if (!_previewLoadOperations || [_previewLoadOperations indexOfObjectIdenticalTo:operation] == NSNotFound) {
        // Operation that was started and then cancelled too late so that it actually fired.
        return;
    }

    PREVIEW_DEBUG(@"%s add preview:%@ view:%p current size:%@", __PRETTY_FUNCTION__, [preview shortDescription], self, NSStringFromCGSize(self.frame.size));

    // Don't explode if the preview fails to load and there is no default.
    if (preview) {
        // If our previewed items changed, then we should have cancelled our existing load operations
        OBASSERT([[self previewedFileItems] member:preview.fileItem] == preview.fileItem);
        
        [_previewView addPreview:preview];
    }
    
    [_previewLoadOperations removeObject:operation];
    if ([_previewLoadOperations count] == 0) {
        [_previewLoadOperations release];
        _previewLoadOperations = nil;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:OUIDocumentPickerItemViewPreviewsDidLoadNotification object:self];
    }
    
    // If the preview was a placeholder, start generating a real preview.
    if (preview.type == OUIDocumentPreviewTypePlaceholder) {
        OBFinishPortingLater("If we got a zero-length preview file, we shouldn't do this. Need to know why the preview is a placeholder so we avoid spinning.");
        
        // Fake a content change to regenerate a preview
        [_item.documentStore _fileItemContentsChanged:preview.fileItem];
    }
}

#pragma mark -
#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &ItemContext) {
        if (OFISEQUAL(keyPath, OUIDocumentStoreItemNameBinding))
            [self _nameChanged];
        else if (OFISEQUAL(keyPath, OUIDocumentStoreItemDateBinding))
            [self _dateChanged];
        else if (OFISEQUAL(keyPath, OUIDocumentStoreItemReadyBinding)) {
            if (self.window)
                [self startLoadingPreviews];
        } else if (OFISEQUAL(keyPath, OUIDocumentStoreItemHasUnresolvedConflictsBinding) ||
                 OFISEQUAL(keyPath, OUIDocumentStoreItemIsDownloadedBinding) ||
                 OFISEQUAL(keyPath, OUIDocumentStoreItemIsDownloadingBinding) ||
                 OFISEQUAL(keyPath, OUIDocumentStoreItemIsUploadedBinding) ||
                 OFISEQUAL(keyPath, OUIDocumentStoreItemIsUploadingBinding) ||
                 OFISEQUAL(keyPath, OUIDocumentStoreItemPercentDownloadedBinding) ||
                 OFISEQUAL(keyPath, OUIDocumentStoreItemPercentUploadedBinding)) {
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
    
    _previewView.showsProgress = showProgress;
    _previewView.progress = percent / 100;
}

@end
