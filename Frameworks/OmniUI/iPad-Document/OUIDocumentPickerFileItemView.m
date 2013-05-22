// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>

#import <OmniUIDocument/OUIDocumentPreviewView.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFoundation/OFBinding.h>

#import "OUIDocumentPickerItemNameAndDateView.h"
#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIDocumentParameters.h"

RCS_ID("$Id$");

@interface OUIDocumentPickerFileItemView ()
- (void)_selectedChanged;
@end

@implementation OUIDocumentPickerFileItemView

static id _commonInit(OUIDocumentPickerFileItemView *self)
{
#if 0 && defined(DEBUG_bungi)
    self.backgroundColor = [UIColor redColor];
#endif
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

- (void)itemChanged;
{
    [super itemChanged];

    // We do NOT set self.draggingState to OUIDocumentPickerItemViewSourceDraggingState based on fileItem.draggingSource, but let our container control this.
    // We might be a dragging view (in which case we aren't the source view itself).
    
    [self _selectedChanged];
    [self _downloadRequestedChanged];
}

- (OUIDocumentPreview *)preview;
{
    NSArray *previews = self.previewView.previews;
    OBASSERT([previews count] <= 1);
    return [previews lastObject];
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

#pragma mark - Accessibility
- (NSString *)accessibilityLabel;
{
    OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)self.item;
    OBASSERT(!fileItem || [fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);
    
    // Accessibilit label should read: Name, Badge Status (if any), Modification Date, iCloud Exclusion (if any)
    
    // Name
    NSMutableString *label = [NSMutableString stringWithFormat:@"%@.", fileItem.name];
    
    // Badge Status
    NSString *badgeStatus = nil;
    if (fileItem.isDownloaded == NO) {
        badgeStatus = NSLocalizedStringFromTableInBundle(@"Not downloaded", @"OmniUIDocument", OMNI_BUNDLE, @"Not downloaded accessibility label.");
    }
    else if (fileItem.isUploaded == NO) {
        badgeStatus = NSLocalizedStringFromTableInBundle(@"Not uploaded", @"OmniUIDocument", OMNI_BUNDLE, @"Not uploaded accessibility label.");
    }
    
    if (badgeStatus) {
        [label appendFormat:@" %@.", badgeStatus];
    }
    
    
    // Modification Date
    [label appendFormat:@" %@.", [OFSDocumentStoreItem displayStringForDate:fileItem.userModificationDate]];
    
    return label;
}

- (UIAccessibilityTraits)accessibilityTraits;
{
    OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)self.item;
    OBASSERT(!fileItem || [fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);

    if (fileItem.selected) {
        return UIAccessibilityTraitSelected;
    }
    
    return UIAccessibilityTraitNone;
}

#pragma mark -
#pragma mark OUIDocumentPickerItemView subclass

static unsigned FileItemContext;

- (void)startObservingItem:(id)item;
{
    [super startObservingItem:item];
    [item addObserver:self forKeyPath:OFSDocumentStoreFileItemSelectedBinding options:0 context:&FileItemContext];
    [item addObserver:self forKeyPath:OFSDocumentStoreFileItemDownloadRequestedBinding options:0 context:&FileItemContext];
}

- (void)stopObservingItem:(id)item;
{
    [super stopObservingItem:item];
    [item removeObserver:self forKeyPath:OFSDocumentStoreFileItemSelectedBinding context:&FileItemContext];
    [item removeObserver:self forKeyPath:OFSDocumentStoreFileItemDownloadRequestedBinding context:&FileItemContext];
}

- (NSSet *)previewedFileItems;
{
    OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)self.item;
    OBASSERT(!fileItem || [fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);

    if (fileItem)
        return [NSSet setWithObject:fileItem];
    return nil;
}

- (void)setDraggingState:(OUIDocumentPickerItemViewDraggingState)draggingState;
{
    [super setDraggingState:draggingState];
    
    // OBFinishPorting: Add/remove the drag destination halo view later.
    if (draggingState == OUIDocumentPickerItemViewDestinationDraggingState)
        self.backgroundColor = [UIColor greenColor];
    else
        self.backgroundColor = nil;
}

#pragma mark -
#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &FileItemContext) {
        if (OFISEQUAL(keyPath, OFSDocumentStoreFileItemSelectedBinding))
            [self _selectedChanged];
        else if (OFISEQUAL(keyPath, OFSDocumentStoreFileItemDownloadRequestedBinding))
            [self _downloadRequestedChanged];
        else
            OBASSERT_NOT_REACHED("Unknown KVO keyPath");
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark -
#pragma mark Private

- (void)_selectedChanged;
{
    OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)self.item;
    OBASSERT(!fileItem || [fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);
    
    OUIDocumentPreviewView *previewView = self.previewView;
    
    previewView.selected = fileItem.selected;
}

- (void)_downloadRequestedChanged;
{
    OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)self.item;
    OBASSERT(!fileItem || [fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);

    OUIDocumentPreviewView *previewView = self.previewView;

    previewView.downloadRequested = fileItem.downloadRequested;
}

@end
