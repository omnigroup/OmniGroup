// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "TextViewController.h"

#import <OmniUI/OUIEditableFrame.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUIDocument/OUIDocumentAppController.h>

#import <QuartzCore/QuartzCore.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <OmniFoundation/OFExtent.h>
#import <OmniAppKit/OATextAttachment.h>
#import <OmniAppKit/OATextStorage.h>

#import "AppController.h"
#import "RTFDocument.h"
#import "ImageAttachmentCell.h"

RCS_ID("$Id$");

@interface TextViewController () <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@end

@implementation TextViewController
{
    RTFDocument *_nonretained_document;
}

- init;
{
    return [super initWithNibName:@"TextViewController" bundle:nil];
}

- (void)dealloc;
{
    [_toolbar release];
    [_editor release];
    [super dealloc];
}

#pragma mark -
#pragma mark UIResponder subclass

- (NSUndoManager *)undoManager;
{
    // Make sure we get the document's undo manager, not an implicitly created one from UIWindow!
    return [_nonretained_document undoManager];
}

#pragma mark -
#pragma mark OUIDocumentViewController protocol

@synthesize document = _nonretained_document;

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];

    OUIWithoutAnimating(^{
        // Don't steal the toolbar items from any possibly open document
        if (!self.forPreviewGeneration) {
            _toolbar.items = [[OUIDocumentAppController controller] toolbarItemsForDocument:self.document];
            [_toolbar layoutIfNeeded];
        }
        
#if 0
        self.view.layer.borderColor = [[UIColor blueColor] CGColor];
        self.view.layer.borderWidth = 2;
        
        _editor.layer.borderColor = [[UIColor colorWithRed:0.33 green:1.0 blue:0.33 alpha:1.0] CGColor];
        _editor.layer.borderWidth = 4;
#endif
        
        _editor.textInset = UIEdgeInsetsMake(4, 4, 4, 4);
        _editor.delegate = self;
        
        OBASSERT(_nonretained_document);
        _editor.attributedText = _nonretained_document.text;
        [self _updateEditorFrame];
        
        [self adjustScaleTo:1];
        [self adjustContentInset];
        [self _scrollTextSelectionToVisibleWithAnimation:NO];
    });
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration;
{
    [self _updateTitleBarButtonItemSizeUsingInterfaceOrientation:toInterfaceOrientation];
    
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
}

- (void)willMoveToParentViewController:(UIViewController *)parent;
{
    if (parent) {
        [self _updateTitleBarButtonItemSizeUsingInterfaceOrientation:[[UIApplication sharedApplication] statusBarOrientation]];
    }
    
    [super willMoveToParentViewController:parent];
}

#pragma mark -
#pragma mark UIViewController (OUIMainViewControllerExtensions)

- (UIToolbar *)toolbarForMainViewController;
{
    if (!_toolbar)
        [self view]; // It's in our xib
    OBASSERT(_toolbar);
    return _toolbar;
}

#pragma mark OUIEditableFrameDelegate

static CGFloat kPageWidth = (72*8.5); // Vaguely something like 8.5x11 width.

- (void)textViewContentsChanged:(OUIEditableFrame *)textView;
{
    [self _updateEditorFrame];
    
    // We need more of a text storage model so that selection changes can participate in undo.
    _nonretained_document.text = textView.attributedText;

    // Setting the frame will invalidate layout, which we need for selection rect queries.
    [_editor textUsedSize];
    
    [self _scrollTextSelectionToVisibleWithAnimation:YES];
}

- (void)textViewSelectionChanged:(OUIEditableFrame *)textView;
{
    [self _scrollTextSelectionToVisibleWithAnimation:YES];
}

#pragma mark -
#pragma mark OUIScalingViewController subclass

- (CGSize)canvasSize;
{
    if (!_editor)
        return CGSizeZero; // Don't know our canvas size yet. We'll set up initial scaling in -viewDidLoad.
    
    CGSize size;
    size.width = kPageWidth;
    size.height = _editor.textUsedSize.height;

    return size;
}

#pragma mark -
#pragma mark UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView;
{
    return _editor;
}

#pragma mark -
#pragma mark Actions

- (void)attachImage:(id)sender;
{    
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;

    UIPopoverController *popover = [[UIPopoverController alloc] initWithContentViewController:picker];
    [picker release];
        
    [[OUIAppController controller] presentPopover:popover fromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    [popover release];
}

#pragma mark -
#pragma mark UIImagePickerControllerDelegate

- (void)_addAttachmentFromAsset:(ALAsset *)asset;
{
    ALAssetRepresentation *rep = [asset defaultRepresentation];
    NSMutableData *data = [NSMutableData dataWithLength:[rep size]];
    
    NSError *error = nil;
    if ([rep getBytes:[data mutableBytes] fromOffset:0 length:[rep size] error:&error] == 0) {
        NSLog(@"error getting asset data %@", [error toPropertyList]);
    } else {
        NSFileWrapper *wrapper = [[[NSFileWrapper alloc] initRegularFileWithContents:data] autorelease];
        wrapper.filename = [[rep url] lastPathComponent];
        
        // a real implementation would really check that the UTI inherits from public.image here (we could get movies any maybe PDFs in the future) and would provide an appropriate cell class for the type (or punt and not create an attachment).
        OATextAttachment *attachment = [[[OATextAttachment alloc] initWithFileWrapper:wrapper] autorelease];
        ImageAttachmentCell *cell = [[ImageAttachmentCell alloc] init];
        attachment.attachmentCell = cell;
        OBASSERT(cell.attachment == attachment); // sets the backpointer
        [cell release];
        
        UITextRange *selectedTextRange = [_editor selectedTextRange];
        if (!selectedTextRange) {
            UITextPosition *endOfDocument = [_editor endOfDocument];
            selectedTextRange = [_editor textRangeFromPosition:endOfDocument toPosition:endOfDocument];
        }
        UITextPosition *startPosition = [[[selectedTextRange start] copy] autorelease]; // hold onto this since the edit will drop the -selectedTextRange

        // TODO: Clone attributes of the beginning of the selected range?
        unichar attachmentCharacter = OAAttachmentCharacter;
        [_editor replaceRange:selectedTextRange withText:[NSString stringWithCharacters:&attachmentCharacter length:1]];
        
        // This will have changed the selection
        UITextPosition *endPosition = [_editor positionFromPosition:startPosition offset:1];
        selectedTextRange = [_editor textRangeFromPosition:startPosition toPosition:endPosition];

        [_editor setValue:attachment forAttribute:OAAttachmentAttributeName inRange:selectedTextRange];
        
        //NSLog(@"_editor = %@, text = %@", _editor, [_editor attributedText]);
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info;
{
    ALAssetsLibrary *library = [[[ALAssetsLibrary alloc] init] autorelease];
    [library assetForURL:[info objectForKey:UIImagePickerControllerReferenceURL]
             resultBlock:^(ALAsset *asset){
                 // This get called asynchronously (possibly after a permissions question to the user).
                 [self _addAttachmentFromAsset:asset];
             }
            failureBlock:^(NSError *error){
                NSLog(@"error finding asset %@", [error toPropertyList]);
            }];
    
    [[OUIAppController controller] dismissPopoverAnimated:YES];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker;
{
    [[OUIAppController controller] dismissPopoverAnimated:YES];
}

#pragma mark -
#pragma mark Private

- (void)_updateEditorFrame;
{
    CGFloat usedHeight = _editor.viewUsedSize.height;
    _editor.frame = CGRectMake(0, 0, kPageWidth, usedHeight);
}

static const CGFloat kScrollContext = 66;

#if 0 && defined(DEBUG)
    #define DEBUG_SCROLL(format, ...) NSLog(@"SCROLL: " format, ## __VA_ARGS__)
#else
    #define DEBUG_SCROLL(format, ...) do {} while (0)
#endif

static CGFloat _scrollCoord(OFExtent containerExtent, OFExtent innerExtent)
{
    CGFloat minEdgeDistance = fabs(OFExtentMin(containerExtent) - OFExtentMin(innerExtent));
    CGFloat maxEdgeDistance = fabs(OFExtentMax(containerExtent) - OFExtentMax(innerExtent));
    
    DEBUG_SCROLL(@"  minEdgeDistance %f, maxEdgeDistance %f", minEdgeDistance, maxEdgeDistance);
    
    if (minEdgeDistance < maxEdgeDistance) {
        return OFExtentMin(innerExtent);
    } else {
        return OFExtentMax(innerExtent) - OFExtentLength(containerExtent);
    }
}

static void _scrollVerticallyInView(UIScrollView *scrollView, UIView *view, CGRect viewRect, BOOL animated)
{
    DEBUG_SCROLL(@"vertical: view:%@ viewRect %@ animated", [view shortDescription], NSStringFromCGRect(viewRect));
    
    CGRect targetViewRect = [scrollView convertRect:viewRect fromView:view];
    DEBUG_SCROLL(@"  targetViewRect %@", NSStringFromCGRect(targetViewRect));
    
    CGRect scrollBounds = scrollView.bounds;
    
    OFExtent targetViewYExtent = OFExtentFromRectYRange(targetViewRect);
    OFExtent scrollBoundsYExtent = OFExtentFromRectYRange(scrollBounds);
    
    DEBUG_SCROLL(@"  targetViewYExtent = %@, scrollBoundsYExtent = %@", OFExtentToString(targetViewYExtent), OFExtentToString(scrollBoundsYExtent));
    DEBUG_SCROLL(@"  scroll bounds %@, scroll offset %@", NSStringFromCGRect(scrollView.bounds), NSStringFromCGPoint(scrollView.contentOffset));
    
    if (OFExtentMin(targetViewYExtent) < OFExtentMin(scrollBoundsYExtent) + kScrollContext) {
        CGFloat extraScrollPadding = CLAMP(kScrollContext, 0.0f, scrollView.contentOffset.y);
        targetViewYExtent.length += extraScrollPadding; // When we scroll, try to show a little context on the other side
        targetViewYExtent.location -= extraScrollPadding; // If we're scrolling up, we want our target to extend up rather than down
    } else {
        CGFloat extraScrollPadding = CLAMP(kScrollContext, 0.0f, OFExtentLength(scrollBoundsYExtent) - OFExtentLength(targetViewYExtent));
        targetViewYExtent.length += extraScrollPadding; // When we scroll, try to show a little context on the other side
    }
    
    if (OFExtentContainsExtent(scrollBoundsYExtent, targetViewYExtent)) {
        DEBUG_SCROLL(@"  already visible");
        return; // Already fully visible
    }
    
    if (OFExtentContainsExtent(targetViewYExtent, scrollBoundsYExtent)) {
        DEBUG_SCROLL(@"  everything visible is already within the target");
        return; // Everything visible is already within the target
    }
    
    CGPoint contentOffset = scrollView.contentOffset;
    contentOffset.y = _scrollCoord(scrollBoundsYExtent, targetViewYExtent);
    
    // UIScrollView ignores +[UIView areAnimationsEnabled]. Don't provoke animation when we shouldn't be animating.
    animated &= [UIView areAnimationsEnabled];
    
    [scrollView setContentOffset:contentOffset animated:animated];
}

- (void)_scrollTextSelectionToVisibleWithAnimation:(BOOL)animated;
{
    UITextRange *selection = _editor.selectedTextRange;
    if (selection && [_editor window]) {
        CGRect selectionRect = [_editor boundsOfRange:_editor.selectedTextRange];
        _scrollVerticallyInView(self.scrollView, _editor, selectionRect, animated);
    }
}

- (void)_updateTitleBarButtonItemSizeUsingInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    AppController *controller = [AppController controller];    
    UIBarButtonItem *titleItem = [controller documentTitleToolbarItem];
    UIView *customView = titleItem.customView;
    
    OBASSERT_NOTNULL(customView);

    CGFloat newWidth = UIInterfaceOrientationIsPortrait(interfaceOrientation) ? 400 : 550;

    customView.frame = (CGRect){
        .origin.x = customView.frame.origin.x,
        .origin.y = customView.frame.origin.y,
        .size.width = newWidth,
        .size.height = customView.frame.size.height
    };
}

@end
