// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentPickerDragSession.h"

#import <OmniFoundation/OFExtent.h>
#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFileStore/OFSDocumentStoreGroupItem.h>
#import <OmniUI/OUIAnimationSequence.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPreviewView.h>
#import <OmniUI/OUIDragGestureRecognizer.h>
#import <OmniUI/UIGestureRecognizer-OUIExtensions.h>
#import <OmniUI/UIScrollView-OUIExtensions.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import "OUIDocumentPickerItemView-Internal.h"

RCS_ID("$Id$");

#if 1 && defined(DEBUG)
    #define DEBUG_DRAG_AUTOSCROLL(format, ...) NSLog(@"DRAG AUTO: " format, ## __VA_ARGS__)
#else
    #define DEBUG_DRAG_AUTOSCROLL(format, ...) do {} while (0)
#endif

@interface OUIDocumentPickerDragSession ()
- (void)_startDrag;
- (void)_updateDrag;
- (void)_finishDrag;
- (void)_cancelDrag;
- (void)_dragAutoscrollTimerFired:(NSTimer *)timer;
@end

@implementation OUIDocumentPickerDragSession
{
    OUIDocumentPicker *_picker;
    NSSet *_fileItems;
    OUIDragGestureRecognizer *_dragRecognizer;
    
    NSArray *_fileItemViews; // our dragging views, not those from the picker scroll view
    
    id _dragDestinationItem;
    
    CGPoint _startingOffsetWithinDraggingFileItemView;
    NSTimer *_autoscrollTimer;
}

- initWithDocumentPicker:(OUIDocumentPicker *)picker fileItems:(NSSet *)fileItems recognizer:(OUIDragGestureRecognizer *)dragRecognizer;
{
    OBFinishPorting;
#if 0
    OBPRECONDITION(picker);
    OBPRECONDITION([fileItems count] >= 1);
    OBPRECONDITION([fileItems isSubsetOfSet:picker.documentStore.fileItems]);
    OBPRECONDITION(dragRecognizer);
    OBPRECONDITION(dragRecognizer.state == UIGestureRecognizerStateBegan);
    
    if (!(self = [super init]))
        return nil;
    
    _picker = [picker retain];
    _fileItems = [fileItems copy];
    _dragRecognizer = [dragRecognizer retain];
    
    return self;
#endif
}

- (void)dealloc;
{
    [_autoscrollTimer invalidate];
}

@synthesize fileItems = _fileItems;

- (void)handleRecognizerChange;
{
    if (!_fileItems) {
        OBASSERT_NOT_REACHED("Called after being cancelled");
        return;
    }
    
    switch (_dragRecognizer.state) {
        case UIGestureRecognizerStateBegan:
            [self _startDrag];
            break;
        case UIGestureRecognizerStateChanged:
            [self _updateDrag];
            break;
        case UIGestureRecognizerStateEnded:
            [self _finishDrag];
            break;
        case UIGestureRecognizerStateCancelled:
            [self _cancelDrag];
            break;
        default:
            OBASSERT_NOT_REACHED("Unhandled recognizer state");
            break;
    }
}

@synthesize dragDestinationItem = _dragDestinationItem;

- (void)_startDrag;
{
    /*
     To avoid complicating OUIDocumentPickerScrollView (as much), we don't steal its item views for the drag, but make our own. We *do* let the scroll view know that the file items are the source of a drag so that it can draw blank placeholders for them.
     */
    OUIWithoutAnimating(^{
        OUIDocumentPickerScrollView *pickerScrollView = _picker.activeScrollView;
        
        NSMutableArray *fileItemViews = [[NSMutableArray alloc] init];
        for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
            fileItem.draggingSource = YES;
            
            OUIDocumentPickerFileItemView *originalFileItemView = [pickerScrollView fileItemViewForFileItem:fileItem];
            if (!originalFileItemView)
                continue; // scrolled out of view
            
            originalFileItemView.draggingState = OUIDocumentPickerItemViewSourceDraggingState;
            
            OUIDocumentPickerFileItemView *dragFileItemView = [[OUIDocumentPickerFileItemView alloc] init];
            dragFileItemView.frame = originalFileItemView.frame;
            dragFileItemView.item = fileItem;
            
            OUIDocumentPreview *preview = originalFileItemView.preview;
            if (preview)
                [dragFileItemView.previewView addPreview:preview];
            
            [pickerScrollView addSubview:dragFileItemView];
            [fileItemViews addObject:dragFileItemView];
        }
        
        _fileItemViews = [fileItemViews copy];
        OBASSERT([_fileItemViews count] > 0); // some might be off screen, but they can't ALL be
        
        OBFinishPortingLater("If one view is on screen and the others are off, we should really make a few other views for the purpose of flying them into a pile for a group drag."); // might also be good to make at least one or two above the viewport and one below to indicate that all the views came together.
    });
    
    // Remember the touch offset within the file item view that initiated the drag
    {
        OUIDocumentPickerScrollView *pickerScrollView = _picker.activeScrollView;
        UIView *hitView = _dragRecognizer.hitView;
        OUIDocumentPickerFileItemView *fileItemView = [hitView containingViewOfClass:[OUIDocumentPickerFileItemView class]];
        OBASSERT(fileItemView);
        
        CGPoint location = [_dragRecognizer locationInView:pickerScrollView];
        CGRect fileItemFrame = fileItemView.frame;
        
        _startingOffsetWithinDraggingFileItemView = CGPointMake(location.x - fileItemFrame.origin.x, location.y - fileItemFrame.origin.y);
    }
}

- (void)_updateDrag;
{
    OUIDocumentPickerScrollView *pickerScrollView = _picker.activeScrollView;
    
    // TODO: Collapse the dragged file item views into a single group when the drag has proceeded far enough

    // Adjust the postion of the drag.
    CGPoint dragPoint = [_dragRecognizer locationInView:pickerScrollView];
    for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews) {
        OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)fileItemView.item;
        OBASSERT([fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);
        
        CGRect frame = [_picker.mainScrollView frameForItem:fileItem]; // normal position
        
        frame.origin.x = dragPoint.x - _startingOffsetWithinDraggingFileItemView.x;
        frame.origin.y = dragPoint.y - _startingOffsetWithinDraggingFileItemView.y;
        
        fileItemView.frame = frame;
    }
    
    // Hit test the original file items and see if we are over something
    {
        OUIDocumentPickerItemView *itemView = [_picker.activeScrollView itemViewHitInPreviewAreaByRecognizer:_dragRecognizer];
        OFSDocumentStoreItem *item = itemView.item;
        
        id dragDestinationItem = nil;
        if (item && [_fileItems member:item] == nil)
            dragDestinationItem = item;
        
        if (_dragDestinationItem != dragDestinationItem) {
            _dragDestinationItem = dragDestinationItem;
            
            // This will update flags on the scroll view's item views and relayout
            _picker.activeScrollView.draggingDestinationItem = dragDestinationItem;
        }
    }
    
    // Start/stop autoscroll. UITableView edit mode seems to be simply related to the portion off screen. That is, if you hold a row Npx off screen, the speed of the autoscroll stays the same no matter how long you hold it there (as opposed to AppleTV where holding down the scroll accelerates over time). The exact relationship between the offscreen amount/fraction and the scroll speed isn't obvious, so we'll have to tweak it.
    {
        if ([pickerScrollView shouldAutoscrollWithRecognizer:_dragRecognizer allowedDirections:OUIAutoscrollDirectionUp|OUIAutoscrollDirectionDown]) {
            if (!_autoscrollTimer) {
                _autoscrollTimer = [NSTimer scheduledTimerWithTimeInterval:pickerScrollView.autoscrollTimerInterval target:self selector:@selector(_dragAutoscrollTimerFired:) userInfo:nil repeats:YES];
            }
        } else {
            if (_autoscrollTimer) {
                DEBUG_DRAG_AUTOSCROLL(@"Autoscroll end");
                [_autoscrollTimer invalidate];
                _autoscrollTimer = nil;
            }
        }
    }
}

- (void)_finishDrag;
{
    // Stop any autoscroll timer before starting animations since the animation running could let the timer fire again.
    [_autoscrollTimer invalidate];
    _autoscrollTimer = nil;

    if (_dragDestinationItem == nil) {
        // Just snap back
        [OUIAnimationSequence runWithDuration:0.2 actions:
         ^{
             for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews) {
                 // Don't ask for the original item view; the rect for where that would appear may be off screen and the scroll view may not have a view assigned to that file.
                 OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)fileItemView.item;
                 OBASSERT([fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);

                 fileItemView.frame = [_picker.mainScrollView frameForItem:fileItem];
             }
         },
         ^{
             [self _cancelDrag];
         },
         nil];
        return;
    }
    
#if 0
    if ([_dragDestinationItem isKindOfClass:[OFSDocumentStoreFileItem class]]) {
        // make a new group
        [_picker.documentStore makeGroupWithFileItems:[_fileItems setByAddingObject:_dragDestinationItem] completionHandler:^(OFSDocumentStoreGroupItem *group, NSError *error){
            if (!group) {
                OUI_PRESENT_ERROR(error);
            } else {
                OBFinishPortingLater("after various animations, the group expands to be given an initial name"); OB_UNUSED_VALUE(group);
            }
        }];
    } else if ([_dragDestinationItem isKindOfClass:[OFSDocumentStoreGroupItem class]]) {
        // add to an existing group
        OFSDocumentStoreGroupItem *group = _dragDestinationItem;
        [_picker.documentStore moveItems:_fileItems toFolderNamed:group.name completionHandler:^(OFSDocumentStoreGroupItem *group, NSError *error){
            OBFinishPortingLater("Do some animation/report error");
        }];
    } else if (!_dragDestinationItem) {
        OBFinishPortingLater("remove from current group, if any");
    } else {
        OBASSERT_NOT_REACHED("Unknown drag destination type.");
    }
#endif

    [_picker rescanDocuments];
    
    OBFinishPortingLater("Try to perform the actual drag");
    [self _cancelDrag];
}

- (void)_cancelDrag;
{
    OUIDocumentPickerScrollView *pickerScrollView = _picker.activeScrollView;

    OUIWithoutAnimating(^{
        for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews)
            [fileItemView removeFromSuperview];
    
        for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
            fileItem.draggingSource = NO;
            
            OUIDocumentPickerFileItemView *originalFileItemView = [pickerScrollView fileItemViewForFileItem:fileItem];
            if (!originalFileItemView)
                continue; // scrolled out of view
            
            originalFileItemView.draggingState = OUIDocumentPickerItemViewNoneDraggingState;
        }
    });

    // Mark ourselves as done by clearing our file items
    _fileItems = nil;
    
    // This will likely release and deallocate us, so do this last!
    [_picker dragSessionTerminated];
}

- (void)_dragAutoscrollTimerFired:(NSTimer *)timer;
{
    OUIDocumentPickerScrollView *pickerScrollView = _picker.activeScrollView;
    
    [pickerScrollView performAutoscrollWithRecognizer:_dragRecognizer allowedDirections:OUIAutoscrollDirectionUp|OUIAutoscrollDirectionDown];
    
    // Drop location may change due to the new content offset
    [self _updateDrag];
}

@end
