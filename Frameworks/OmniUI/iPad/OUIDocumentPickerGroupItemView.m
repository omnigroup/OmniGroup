// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentPickerGroupItemView.h>

#import <OmniUI/OUIDocumentPreviewView.h>

#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIDocumentStoreGroupItem.h"

RCS_ID("$Id$");

@implementation OUIDocumentPickerGroupItemView

static id _commonInit(OUIDocumentPickerGroupItemView *self)
{
#if 1 && defined(DEBUG_bungi)
    self.backgroundColor = [UIColor blueColor];
#endif
    
    self.previewView.group = YES;
    
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

#pragma mark -
#pragma mark OUIDocumentPickerItemView subclass

static unsigned GroupItemContext;

- (void)startObservingItem:(id)item;
{
    [super startObservingItem:item];
    [item addObserver:self forKeyPath:OUIDocumentStoreGroupItemFileItemsBinding options:0 context:&GroupItemContext];
}

- (void)stopObservingItem:(id)item;
{
    [super stopObservingItem:item];
    [item removeObserver:self forKeyPath:OUIDocumentStoreGroupItemFileItemsBinding context:&GroupItemContext];
}

- (NSSet *)previewedFileItems;
{
    OUIDocumentStoreGroupItem *item = (OUIDocumentStoreGroupItem *)self.item;
    OBASSERT(!item || [item isKindOfClass:[OUIDocumentStoreGroupItem class]]);
    return item.fileItems;
}

#pragma mark -
#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &GroupItemContext) {
        if (OFISEQUAL(keyPath, OUIDocumentStoreGroupItemFileItemsBinding))
            [self previewedFileItemsChanged];
        else
            OBASSERT_NOT_REACHED("Unknown KVO keyPath");
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

@end
