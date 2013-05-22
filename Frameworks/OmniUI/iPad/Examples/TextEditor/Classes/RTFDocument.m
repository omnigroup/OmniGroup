// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "RTFDocument.h"

#import <OmniFileStore/OFSDocumentStoreFileItem.h> // For -fileURL
#import <OmniQuartz/OQDrawing.h> // For OQCreateImageWithSize()
#import <OmniUI/OUIRTFReader.h>
#import <OmniUI/OUIRTFWriter.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUI/UIView-OUIExtensions.h> // For -snapshotImageWithSize:

#import "TextViewController.h"

RCS_ID("$Id$");

@implementation RTFDocument
{
    NSAttributedString *_text;
}

- initEmptyDocumentToBeSavedToURL:(NSURL *)url error:(NSError **)outError;
{
    if (!(self = [super initEmptyDocumentToBeSavedToURL:url error:outError]))
        return nil;
    
    _text = [[NSAttributedString alloc] init];
    
    return self;
}

- (void)dealloc;
{
    [_text release];
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

#pragma mark -
#pragma mark OUIDocument subclass

- (UIViewController *)makeViewController;
{
    return [[[TextViewController alloc] init] autorelease];
}

+ (NSString *)placeholderPreviewImageNameForFileURL:(NSURL *)fileURL landscape:(BOOL)landscape;
{
    return @"DocumentPreviewPlaceholder.png";
}

static void _writePreview(Class self, NSURL *fileURL, NSDate *date, UIViewController *viewController, BOOL landscape, void (^completionHandler)(void))
{
    // We ping pong back and forth between the main queue and the OUIDocumentPreview background queue here a bit. We want to do as much work as possible on the background queue as possible so that the main queue is available to process user events (like scrolling in the document picker) while previews are being generated. Some code, however, must be done on the main thread. In particular our drawing code is UIView-based and so the preview image must be done on the main queue.
    // One might thing that it would be better to determine the final preview image size and call -snapshotImageWithSize: with that size, but this is (very) wrong. The issue is that the CALayer -renderInContext: method is very slow if it has to scale the layer backing stores, but it is very fast if it can blit them w/o interpolation. So, it is faster to capture a 100% scale image and then do one final scaling operation (which we can also do on the background queue).
    
    completionHandler = [[completionHandler copy] autorelease];

    CGRect viewFrame = landscape ? CGRectMake(0.0f, 0.0f, 1024.0f, 768.0f) : CGRectMake(0.0f, 0.0f, 768.0f, 1024.0f);
    UIView *view = viewController.view;
    view.frame = viewFrame;
    [view layoutIfNeeded];
    UIImage *image = [view snapshotImageWithSize:viewFrame.size];

    // Now we have an image, but it is needs to be scaled down. Do that on the background too.
    [OUIDocumentPreview performAsynchronousPreviewOperation:^{
        CGSize size = [OUIDocumentPreview maximumPreviewSizeForLandscape:landscape];
        CGFloat scale = [OUIDocumentPreview previewImageScale];
        size.width = floor(size.width * scale);
        size.height = floor(size.height * scale);
        CGImageRef scaledImage = OQCreateImageWithSize([image CGImage], size, kCGInterpolationHigh);
        
        // Back to the main thread to cache the image!
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [OUIDocumentPreview cachePreviewImages:^(OUIDocumentPreviewCacheImage cacheImage) {
                cacheImage(fileURL, date, landscape, scaledImage);
                CFRelease(scaledImage);
            }];

            // Don't invoke the handler directly -- we want control to return to the runloop to process any pending events/scrolling
            if (completionHandler)
                [[NSOperationQueue mainQueue] addOperationWithBlock:completionHandler];
        }];
    }];
}

+ (void)writePreviewsForDocument:(OUIDocument *)document withCompletionHandler:(void (^)(void))completionHandler;
{
    // A useful pattern is to make a new view controller that is preconfigured to know that it will only ever be used to generate a preview (by propagating the UIDocument.forPreviewGeneration flag). In this case, the view controller can only load the data necessary to show a preview (data that might not be present in the current view controller if it is scrolled out of view). For example, in OmniOutliner for iPad, we make a new view controller that only loads N rows (based on the minimum row height and orientation).
    
    TextViewController *viewController;

    if (document.forPreviewGeneration) {
        // Just use the default view controller -- no one else is
        viewController = (TextViewController *)document.viewController;
    } else {
        // Make a new view controller so we can assume it is not scrolled down or has a different viewport.
        viewController = (TextViewController *)[document makeViewController];
        viewController.document = document;
    }
    viewController.forPreviewGeneration = YES;
    
    viewController.scrollView.contentOffset = CGPointZero;
    
    OFSDocumentStoreFileItem *fileItem = document.fileItem;
    NSURL *fileURL = fileItem.fileURL;
    NSDate *date = fileItem.fileModificationDate;

    completionHandler = [[completionHandler copy] autorelease];
    
    _writePreview(self, fileURL, date, viewController, NO, ^{
        _writePreview(self, fileURL, date, viewController, YES, ^{
            if (completionHandler)
                completionHandler();
        });
    });
}

#pragma mark -
#pragma mark UIDocument subclass

- (BOOL)readFromURL:(NSURL *)url error:(NSError **)outError;
{    
    NSString *rtfString = [[NSString alloc] initWithContentsOfURL:url encoding:NSUTF8StringEncoding error:outError];
    if (!rtfString)
        return NO;
    
    NSAttributedString *attributedString = [OUIRTFReader parseRTFString:rtfString];
    [rtfString release];
    
    if (!attributedString) {
        // TODO: Better handling
        OBFinishPorting;
    }
    
    [_text release];
    _text = [attributedString copy];
    
    return YES;
}

- (BOOL)writeContents:(id)contents toURL:(NSURL *)url forSaveOperation:(UIDocumentSaveOperation)saveOperation originalContentsURL:(NSURL *)originalContentsURL error:(NSError **)outError;
{
    // TODO: Ask the text editor to finish any edits/undo groups. Might be in the middle of marked text, for example.
    // TODO: Save a preview PDF somewhere.
    
    NSData *data = [OUIRTFWriter rtfDataForAttributedString:_text];
    return [data writeToURL:url options:0 error:outError];
}

@end
