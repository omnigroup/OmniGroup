// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>

#import <OmniUIDocument/OUIDocumentPreviewView.h>
#import <OmniUIDocument/OUIDocumentPickerItemMetadataView.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniFoundation/OFBinding.h>

#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIDocumentParameters.h"

RCS_ID("$Id$");

@implementation OUIDocumentPickerFileItemView

static id _commonInit(OUIDocumentPickerFileItemView *self)
{
#if 0 && defined(DEBUG_bungi)
    self.backgroundColor = [UIColor redColor];
#endif
    
    UIView *contentView = self.contentView;
    OUIDocumentPreviewView *previewView = [[OUIDocumentPreviewView alloc] initWithFrame:contentView.bounds];
    previewView.translatesAutoresizingMaskIntoConstraints = self.translatesAutoresizingMaskIntoConstraints;
    [contentView addSubview:previewView];
    if (self.translatesAutoresizingMaskIntoConstraints) {
        previewView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    } else {
        NSMutableArray *constraints = [NSMutableArray array];
        [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[previewView]|"
                                                                                 options:kNilOptions
                                                                                 metrics:nil
                                                                                   views:NSDictionaryOfVariableBindings(previewView)]];
        [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[previewView]|"
                                                                                 options:kNilOptions
                                                                                 metrics:nil
                                                                                   views:NSDictionaryOfVariableBindings(previewView)]];
        [NSLayoutConstraint activateConstraints:constraints];
    }
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
    
    [self _downloadRequestedChanged];
}

#pragma mark -
#pragma mark OUIDocumentPickerItemView subclass

static unsigned FileItemContext;

- (void)startObservingItem:(id)item;
{
    [super startObservingItem:item];
    [item addObserver:self forKeyPath:ODSFileItemDownloadRequestedBinding options:0 context:&FileItemContext];
}

- (void)stopObservingItem:(id)item;
{
    [super stopObservingItem:item];
    [item removeObserver:self forKeyPath:ODSFileItemDownloadRequestedBinding context:&FileItemContext];
}

- (NSArray *)previewedItems;
{
    ODSFileItem *fileItem = (ODSFileItem *)self.item;
    OBASSERT(!fileItem || [fileItem isKindOfClass:[ODSFileItem class]]);

    if (fileItem)
        return [NSArray arrayWithObject:fileItem];
    return nil;
}

- (void)setDraggingState:(OUIDocumentPickerItemViewDraggingState)draggingState;
{
    [super setDraggingState:draggingState];
    
    // OBFinishPorting: <bug:///147827> (iOS-OmniOutliner Bug: OUIDocumentPickerFileItemView.m:105: Add/remove the drag destination halo view later)
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
        if (OFISEQUAL(keyPath, ODSFileItemDownloadRequestedBinding))
            [self _downloadRequestedChanged];
        else
            OBASSERT_NOT_REACHED("Unknown KVO keyPath");
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - Private

- (void)_downloadRequestedChanged;
{
    // <bug:///94069> (File item views not showing the 'downloaded requested' state
#if 0
    ODSFileItem *fileItem = (ODSFileItem *)self.item;
    OBASSERT(!fileItem || [fileItem isKindOfClass:[ODSFileItem class]]);

    OUIDocumentPreviewView *previewView = self.previewView;

    previewView.downloadRequested = fileItem.downloadRequested;
#endif
}

@end
