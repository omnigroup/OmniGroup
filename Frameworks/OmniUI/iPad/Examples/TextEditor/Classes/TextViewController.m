// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "TextViewController.h"

#import <OmniUI/OUIEditableFrame.h>
#import <OmniUI/OUIAppController.h>

#import <QuartzCore/QuartzCore.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <OmniFoundation/OFFileWrapper.h>
#import <OmniAppKit/OATextAttachment.h>
#import <OmniAppKit/OATextStorage.h>

#import "RTFDocument.h"
#import "ImageAttachmentCell.h"

RCS_ID("$Id$");

@interface TextViewController () <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@end

@implementation TextViewController

- init;
{
    return [super initWithNibName:@"TextViewController" bundle:nil];
}

- (void)dealloc;
{
    [_editor release];
    [super dealloc];
}

@synthesize editor = _editor;

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

#if 0
    self.view.layer.borderColor = [[UIColor blueColor] CGColor];
    self.view.layer.borderWidth = 2;
    
    _editor.layer.borderColor = [[UIColor colorWithRed:0.33 green:1.0 blue:0.33 alpha:1.0] CGColor];
    _editor.layer.borderWidth = 4;
#endif
    
    _editor.textInset = UIEdgeInsetsMake(4, 4, 4, 4);
    _editor.delegate = self;
    
    _editor.attributedText = _nonretained_document.text;
    [self textViewContentsChanged:_editor];
    
    [self adjustScaleTo:1];
    [self adjustContentInset];
}

- (void)viewDidUnload;
{
    self.editor = nil;
    [super viewDidUnload];
}

#pragma mark OUIEditableFrameDelegate

static CGFloat kPageWidth = (72*8.5); // Vaguely something like 8.5x11 width.

- (void)textViewContentsChanged:(OUIEditableFrame *)textView;
{
    CGFloat usedHeight = _editor.viewUsedSize.height;
    _editor.frame = CGRectMake(0, 0, kPageWidth, usedHeight);
}

- (void)textViewDidEndEditing:(OUIEditableFrame *)textView;
{
    // We need more of a text storage model so that selection changes can participate in undo.
    _nonretained_document.text = textView.attributedText;
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
        OFFileWrapper *wrapper = [[[OFFileWrapper alloc] initRegularFileWithContents:data] autorelease];
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

@end
