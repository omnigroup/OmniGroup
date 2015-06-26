// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "TextDocument.h"

#import <OmniDocumentStore/ODSFileItem.h> // For -fileURL
#import <OmniQuartz/OQDrawing.h> // For OQCreateImageWithSize()
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUI/UIView-OUIExtensions.h> // For -snapshotImageWithSize:
#import <OmniAppKit/NSAttributedString-OAExtensions.h>
#import <MobileCoreServices/MobileCoreServices.h>

#import "TextViewController.h"

RCS_ID("$Id$");

@implementation TextDocument
{
    NSAttributedString *_text;
    UINavigationController *_viewControllerToPresent;
}

- initWithContentsOfTemplateAtURL:(NSURL *)templateURLOrNil toBeSavedToURL:(NSURL *)saveURL error:(NSError **)outError;
{
    OBPRECONDITION(templateURLOrNil == nil, "We don't have template support");

    if (!(self = [super initWithContentsOfTemplateAtURL:templateURLOrNil toBeSavedToURL:saveURL error:outError]))
        return nil;
    
    _text = [[NSAttributedString alloc] init];
    _scale = 1;
    
    return self;
}

- (void)dealloc;
{
    [_text release];
    [_viewControllerToPresent release];
    [super dealloc];
}

@synthesize text = _text;
- (void)setText:(NSAttributedString *)text;
{
    if (OFISEQUAL(_text, text))
        return;
    
    [_text release];
    _text = [text copy];
    
    // We don't support undo right now, but at least poke the UIDocument autosave timer.
    [self updateChangeCount:UIDocumentChangeDone];
}

- (void)setScale:(CGFloat)scale;
{
    TextViewController *vc = (TextViewController *)self.documentViewController;
    _scale = scale;
    vc.scale = scale;
}

#pragma mark -
#pragma mark OUIDocument subclass

- (UIViewController *)makeViewController;
{
    TextViewController *vc = [[[TextViewController alloc] init] autorelease];
    vc.scale = _scale;
    return vc;
}

- (UIViewController *)viewControllerToPresent;
{
    if (_viewControllerToPresent == nil) {
        _viewControllerToPresent = [[UINavigationController alloc] initWithRootViewController:self.documentViewController];
        _viewControllerToPresent.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    
    return _viewControllerToPresent;
}

- (void)updateViewControllerToPresent;
{
    OBPRECONDITION(self.documentViewController);
    OBPRECONDITION(self.viewControllerToPresent);
    OBPRECONDITION([_viewControllerToPresent.viewControllers count] <= 1); // Right now we only support a single view controller. This may need to be fixed if/when this changes. 0 is also valid.
    
    [(UINavigationController *)self.viewControllerToPresent setViewControllers:@[self.documentViewController] animated:NO];
}

- (void)didClose;
{
    TextViewController *vc = (TextViewController *)self.documentViewController;
    [vc documentDidClose];

    [_viewControllerToPresent release];
    _viewControllerToPresent = nil;
    
    [super didClose];
}

+ (NSString *)placeholderPreviewImageNameForFileURL:(NSURL *)fileURL area:(OUIDocumentPreviewArea)area;
{
    return @"DocumentPreviewPlaceholder.png";
}

static void _writePreview(Class self, OFFileEdit *fileEdit, UIViewController *viewController, void (^completionHandler)(void))
{
    // We ping pong back and forth between the main queue and the OUIDocumentPreview background queue here a bit. We want to do as much work as possible on the background queue as possible so that the main queue is available to process user events (like scrolling in the document picker) while previews are being generated. Some code, however, must be done on the main thread. In particular our drawing code is UIView-based and so the preview image must be done on the main queue.
    // One might thing that it would be better to determine the final preview image size and call -snapshotImageWithSize: with that size, but this is (very) wrong. The issue is that the CALayer -renderInContext: method is very slow if it has to scale the layer backing stores, but it is very fast if it can blit them w/o interpolation. So, it is faster to capture a 100% scale image and then do one final scaling operation (which we can also do on the background queue).
    
    completionHandler = [[completionHandler copy] autorelease];

    CGRect viewFrame = CGRectMake(0.0f, 0.0f, 768.0f, 1024.0f);
    UIView *view = viewController.view;
    view.frame = viewFrame;
    [view layoutIfNeeded];
    
    UIImage *image = [view snapshotImageWithSize:viewFrame.size];
    
    [OUIDocumentPreview cachePreviewImages:^(OUIDocumentPreviewCacheImage cacheImage){
        cacheImage(fileEdit, [image CGImage]);
    }];

    // Don't invoke the handler directly -- we want control to return to the runloop to process any pending events/scrolling
    if (completionHandler)
        [[NSOperationQueue mainQueue] addOperationWithBlock:completionHandler];
}

+ (void)writePreviewsForDocument:(OUIDocument *)document withCompletionHandler:(void (^)(void))completionHandler;
{
    // A useful pattern is to make a new view controller that is preconfigured to know that it will only ever be used to generate a preview (by propagating the UIDocument.forPreviewGeneration flag). In this case, the view controller can only load the data necessary to show a preview (data that might not be present in the current view controller if it is scrolled out of view). For example, in OmniOutliner for iPad, we make a new view controller that only loads N rows (based on the minimum row height and orientation).
    
    TextViewController *viewController;

    if (document.forPreviewGeneration) {
        // Just use the default view controller -- no one else is
        viewController = (TextViewController *)document.documentViewController;
    } else {
        // Make a new view controller so we can assume it is not scrolled down or has a different viewport.
        viewController = (TextViewController *)[document makeViewController];
        viewController.document = document;
    }
    viewController.forPreviewGeneration = YES;
    
    viewController.textView.contentOffset = CGPointZero;
    
    ODSFileItem *fileItem = document.fileItem;
    OFFileEdit *fileEdit = fileItem.fileEdit;

    completionHandler = [[completionHandler copy] autorelease];
    
    _writePreview(self, fileEdit, viewController, ^{
        if (completionHandler)
            completionHandler();
    });
}

#pragma mark -
#pragma mark UIDocument subclass

- (BOOL)readFromURL:(NSURL *)url error:(NSError **)outError;
{
    __autoreleasing NSDictionary *documentAttributes = nil;
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithFileURL:url options:@{} documentAttributes:&documentAttributes error:outError];
    if (!attributedString)
        return NO;
    
    NSNumber *scale = documentAttributes[NSViewZoomDocumentAttribute];
    if (scale) {
        _scale = [scale floatValue] / 100;
        _scale = CLAMP(_scale, 0.25, 3.0);
    } else
        _scale = 1;
    
    // TODO: Make this all less RTF specific (now that NSAttributedString can do plain text, HTML, etc).
    NSLog(@"document attributes = %@", documentAttributes);
    
    [_text release];
    _text = [attributedString copy];
    [attributedString release];
    
    return YES;
}

- (NSString *)savingFileType;
{
    if ([_text containsAttachments])
        return (OB_BRIDGE NSString *)kUTTypeRTFD;
    
    // TODO: If we have "interesting" text attributes, upgrade plain text to rich text.
    // TODO: Downgrade RTFD to RTF when there are no attachments?
    
    return [super savingFileType];
}

- (id)contentsForType:(NSString *)typeName error:(NSError **)outError;
{
    OBPRECONDITION(_text);

    // TODO: Ask the text editor to finish any edits/undo groups. Might be in the middle of marked text, for example.
    
    // It would be much nicer if NSAttributedString used UTI for these types.
    NSString *documentType;
    
    if (UTTypeConformsTo((OB_BRIDGE CFStringRef)typeName, kUTTypeRTFD))
        documentType = NSRTFDTextDocumentType;
    else if (UTTypeConformsTo((OB_BRIDGE CFStringRef)typeName, kUTTypeRTF))
        documentType = NSRTFTextDocumentType;
    else if (UTTypeConformsTo((OB_BRIDGE CFStringRef)typeName, kUTTypePlainText))
        documentType = NSPlainTextDocumentType;
    else {
        NSLog(@"Unknown type name %@", typeName);
        documentType = NSRTFTextDocumentType;
    }
    
    NSLog(@"%@ -> %@", typeName, documentType);
    
    CGFloat scale = _scale * 100;
    
    return [_text fileWrapperFromRange:NSMakeRange(0, [_text length]) documentAttributes:@{NSDocumentTypeDocumentAttribute:documentType, NSViewZoomDocumentAttribute:@(scale)} error:outError];
}

- (BOOL)writeContents:(id)contents toURL:(NSURL *)url forSaveOperation:(UIDocumentSaveOperation)saveOperation originalContentsURL:(NSURL *)originalContentsURL error:(NSError **)outError;
{
    if (![super writeContents:contents toURL:url forSaveOperation:saveOperation originalContentsURL:originalContentsURL error:outError])
        return NO;
    
    [self didWriteToURL:url];
    return YES;
}

@end
