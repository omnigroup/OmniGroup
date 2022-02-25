// Copyright 2010-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "TextViewController.h"

@import OmniUI;
@import OmniUIDocument;

#import <AssetsLibrary/AssetsLibrary.h>
#import <OmniFoundation/OFExtent.h>
#import <OmniAppKit/NSAttributedString-OAExtensions.h>
#import <OmniAppKit/OATextAttachment.h>
#import <OmniFoundation/OFUTI.h>

#import "AppController.h"
#import "TextDocument.h"
#import "TextView.h"

RCS_ID("$Id$");

@interface TextViewController () <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@end

@implementation TextViewController
{
    __weak TextDocument *_weak_document;
    OUIDocumentNavigationItem *_documentNavigationItem;

    OUIScalingTextStorage *_scalingTextStorage;
    NSLayoutManager *_layoutManager;
    NSTextContainer *_textContainer;
    
    BOOL _receivedDocumentDidClose;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    
    _scale = 1;
    
    return self;
}

- init;
{
    return [super initWithNibName:nil bundle:nil];
}

- (void)dealloc;
{
    OUITextView *textView = self.textView;
    textView.delegate = nil;
    
    NSUInteger containerIndex = [[_layoutManager textContainers] indexOfObjectIdenticalTo:_textContainer];
    if (containerIndex != NSNotFound) {
        [_layoutManager removeTextContainerAtIndex:containerIndex];
    }
    
    [_scalingTextStorage removeLayoutManager:_layoutManager];
}

- (OUITextView *)textView;
{
    return (OUITextView *)self.view;
}

- (void)setScale:(CGFloat)scale;
{
    _scale = scale;
    
    if ([self isViewLoaded]) {
        OUIScalingTextStorage *scalingTextStorage = (OUIScalingTextStorage *)self.textView.textStorage;
        scalingTextStorage.scale = scale;
    }
}

- (void)documentDidClose;
{
    OBPRECONDITION(_receivedDocumentDidClose == NO);

    _receivedDocumentDidClose = YES;

    // Break retain cycle.
    _documentNavigationItem = nil;
}

- (OUIDocumentSceneDelegate *)sceneDelegate;
{
    return [[OUIDocumentSceneDelegate documentSceneDelegatesForDocument:self.document] firstObject];
}

#pragma mark - UIResponder subclass

- (NSUndoManager *)undoManager;
{
    // UITextView has a private text view and it doesn't currently like to send its undos to the document undo manager.
    // Hook up our undo/redo options to the text view.
    return self.textView.undoManager;
}

#pragma mark - OUIDocumentViewController protocol

@synthesize document = _weak_document;

- (UIView *)documentOpenCloseTransitionView;
{
    return self.textView;
}

#pragma mark - UIViewController subclass

- (UINavigationItem *)navigationItem;
{
    // Don't re-establish a retain cycle we broke.
    if (!_receivedDocumentDidClose && _documentNavigationItem == nil) {
        TextDocument *document = self.document;
        OBASSERT_NOTNULL(document);

        _documentNavigationItem = [[OUIDocumentNavigationItem alloc] initWithDocument:document];
    }
    
    return _documentNavigationItem;
}

- (void)loadView;
{
    TextDocument *document = _weak_document;

    OBASSERT(document);
    
    NSTextStorage *underlyingTextStorage = [[NSTextStorage alloc] initWithAttributedString:document.text];
    _scalingTextStorage = [[OUIScalingTextStorage alloc] initWithUnderlyingTextStorage:underlyingTextStorage scale:_scale];

    _layoutManager = [[NSLayoutManager alloc] init];
    [_scalingTextStorage addLayoutManager:_layoutManager];
    
    _textContainer = [[NSTextContainer alloc] initWithSize:CGSizeZero];
    _textContainer.widthTracksTextView = YES;
    _textContainer.heightTracksTextView = NO;
    [_layoutManager addTextContainer:_textContainer];
    
    TextView *textView = [[TextView alloc] initWithFrame:CGRectZero textContainer:_textContainer];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    textView.delegate = self;
    
    self.view = textView;
    
    document.undoManager = textView.undoManager;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];

    OUIWithoutAnimating(^{
        // Don't steal the toolbar items from any possibly open document
        if (!self.forPreviewGeneration) {
            OUIDocumentSceneDelegate *sceneDelegate = self.sceneDelegate;
            OUIUndoBarButtonItem *undoItem = [[OUIUndoBarButtonItem alloc] init];
            undoItem.undoBarButtonItemTarget = sceneDelegate;

            // Listed left to right.
            self.navigationItem.leftBarButtonItems = @[
                                                       sceneDelegate.closeDocumentBarButtonItem,
                                                       undoItem
                                                       ];
            
            // Custom title view and OmniPresence Sync button are handled by the OUIDocumentNavigatonItem.
            
            // Listed right to left
            self.navigationItem.rightBarButtonItems = @[
                [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCamera target:self action:@selector(attachImage:)],
                sceneDelegate.infoBarButtonItem,
                [[UIBarButtonItem alloc] initWithImage:[UIImage actionsImage] style:UIBarButtonItemStylePlain target:self action:@selector(_changeDocumentType:)],
            ];
            
        }
        
#if 0
        self.view.layer.borderColor = [[UIColor blueColor] CGColor];
        self.view.layer.borderWidth = 2;
#endif
        
        [self _scrollTextSelectionToVisibleWithAnimation:NO];
    });
}

#pragma mark OUITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView;
{
    // TODO: Just queue an autosave here and make the document vend a text storage.
    NSAttributedString *text = [[NSAttributedString alloc] initWithAttributedString:[textView.textStorage underlyingTextStorage]];
    _weak_document.text = text;

    [self _scrollTextSelectionToVisibleWithAnimation:YES];
}

- (void)textViewDidChangeSelection:(UITextView *)textView;
{
    [self _scrollTextSelectionToVisibleWithAnimation:YES];
}

#pragma mark - Actions

- (void)attachImage:(id)sender;
{    
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationPopover;

    UIPopoverPresentationController *presentation = picker.popoverPresentationController;
    presentation.barButtonItem = sender;
    presentation.permittedArrowDirections = UIPopoverArrowDirectionAny;

    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)_addAttachmentFromAsset:(ALAsset *)asset;
{
    ALAssetRepresentation *rep = [asset defaultRepresentation];
    OBASSERT([rep size] > 0);
#if !defined(__LP64__)
    OBASSERT([rep size] <= NSUIntegerMax); // -size returns long long, which warns on 32-bit
#endif
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)[rep size]];
    
    NSError *error = nil;
    if ([rep getBytes:[data mutableBytes] fromOffset:0 length:(NSUInteger)[rep size] error:&error] == 0) {
        NSLog(@"error getting asset data %@", [error toPropertyList]);
    } else {        
        NSTextAttachment *attachment = [[NSTextAttachment alloc] initWithData:data ofType:rep.UTI];
        
        OUITextView *textView = self.textView;
        NSRange selectedTextRange = textView.selectedRange;
        if (selectedTextRange.location == NSNotFound) {
            selectedTextRange = NSMakeRange(0, [textView.textStorage length]);
        }

        // Keep whatever other attributes we had; doesn't matter now, but if we wanted to draw a label on the attachment, it would be nice to have it know that its foreground color should match the color of the surrounding text.
        NSMutableDictionary *attributes = [[NSMutableDictionary alloc] initWithDictionary:textView.typingAttributes];
        attributes[NSAttachmentAttributeName] = attachment;
        
        NSAttributedString *attachmentAttributedString = [[NSAttributedString alloc] initWithString:[NSAttributedString attachmentString] attributes:attributes];

        // This will change the selection, possibly putting the old selection out of bounds. Don't depend on UITextView handling this...
        BOOL didChangeSelection = NO;
        if (selectedTextRange.length > 1/*[attachmentAttributedString length]*/) {
            // Selection is getting shorter; adjust it now.
            textView.selectedRange = NSMakeRange(selectedTextRange.location + 1, 0);
            didChangeSelection = YES;
        }
        
        NSTextStorage *textStorage = [textView.textStorage underlyingTextStorage];
        [textStorage beginEditing];
        [textStorage replaceCharactersInRange:selectedTextRange withAttributedString:attachmentAttributedString];
        [textStorage endEditing];
        
        if (!didChangeSelection) {
            // Selection is growing, so we waited until now to change it.
            textView.selectedRange = NSMakeRange(selectedTextRange.location + 1, 0);
        }
        
        // Otherwise, this won't mark the document dirty.
        [self textViewDidChange:textView];
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info;
{
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    [library assetForURL:[info objectForKey:UIImagePickerControllerReferenceURL]
             resultBlock:^(ALAsset *asset){
                 // This get called asynchronously (possibly after a permissions question to the user).
                 [self _addAttachmentFromAsset:asset];
             }
            failureBlock:^(NSError *error){
                NSLog(@"error finding asset %@", [error toPropertyList]);
            }];

    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker;
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Private

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

static void _scrollVerticallyInView(OUITextView *textView, CGRect viewRect, BOOL animated)
{
    DEBUG_SCROLL(@"vertical: view:%@ viewRect %@ animated", [view shortDescription], NSStringFromCGRect(viewRect));
    
    CGRect scrollBounds = textView.bounds;
    
    OFExtent targetViewYExtent = OFExtentFromRectYRange(viewRect);
    OFExtent scrollBoundsYExtent = OFExtentFromRectYRange(scrollBounds);
    
    DEBUG_SCROLL(@"  targetViewYExtent = %@, scrollBoundsYExtent = %@", OFExtentToString(targetViewYExtent), OFExtentToString(scrollBoundsYExtent));
    DEBUG_SCROLL(@"  scroll bounds %@, scroll offset %@", NSStringFromCGRect(scrollView.bounds), NSStringFromCGPoint(scrollView.contentOffset));
    
    if (OFExtentMin(targetViewYExtent) < OFExtentMin(scrollBoundsYExtent) + kScrollContext) {
        CGFloat extraScrollPadding = CLAMP(kScrollContext, 0.0f, textView.contentOffset.y);
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
    
    CGPoint contentOffset = textView.contentOffset;
    contentOffset.y = _scrollCoord(scrollBoundsYExtent, targetViewYExtent);
    
    // UIScrollView ignores +[UIView areAnimationsEnabled]. Don't provoke animation when we shouldn't be animating.
    animated &= [UIView areAnimationsEnabled];
    
    [textView setContentOffset:contentOffset animated:animated];
}

- (void)_scrollTextSelectionToVisibleWithAnimation:(BOOL)animated;
{
    OUITextView *textView = self.textView;
    UITextRange *selection = textView.selectedTextRange;
    if (selection && textView.window) {
        CGRect selectionRect = [textView boundsOfRange:selection];
        _scrollVerticallyInView(textView, selectionRect, animated);
    }
}

- (void)_changeDocumentType:(id)sender;
{
    NSString *fileType = OFUTIForFileURLPreferringNative(_weak_document.fileURL, NULL);

    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:OBUnlocalized(@"Change Document Type") message:OBUnlocalized([NSString stringWithFormat:@"Current type is %@", fileType]) preferredStyle:UIAlertControllerStyleAlert];
    
    TextDocument *currentDocument = _weak_document;
    NSArray *types = @[(OB_BRIDGE NSString *)kUTTypePlainText, (OB_BRIDGE NSString *)kUTTypeRTF, (OB_BRIDGE NSString *)kUTTypeRTFD];

    for (NSString *type in types) {
        if (OFTypeConformsToOneOfTypesInArray(fileType, @[type])) {
            continue;
        }
        UIAlertAction *convert = [UIAlertAction actionWithTitle:type style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            currentDocument.preferredSaveUTI = type;
            [_weak_document updateChangeCount:UIDocumentChangeDone];
        }];
        [alertController addAction:convert];
    }
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:OBUnlocalized(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        NSLog(@"Cancel");
    }];
    [alertController addAction:cancel];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

@end
