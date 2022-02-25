// Copyright 2010-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "TextDocument.h"

#import <OmniQuartz/OQDrawing.h> // For OQCreateImageWithSize()
#import <OmniUI/OmniUI.h>
#import <OmniAppKit/NSAttributedString-OAExtensions.h>
#import <MobileCoreServices/MobileCoreServices.h>

#import "TextViewController.h"

RCS_ID("$Id$");

@implementation TextDocument
{
    NSAttributedString *_text;
    UINavigationController *_viewControllerToPresent;
}

+ (NSURL *)builtInBlankTemplateURL;
{
    NSURL *templateURL = [[NSBundle mainBundle] URLForResource:@"Hello" withExtension:@"rtf" subdirectory:@"Samples"];
    return templateURL;
}

- initWithContentsOfTemplateAtURL:(NSURL *)templateURLOrNil toBeSavedToURL:(NSURL *)saveURL activityViewController:(UIViewController *)activityViewController error:(NSError **)outError;
{
    if (!(self = [super initWithContentsOfTemplateAtURL:templateURLOrNil toBeSavedToURL:saveURL activityViewController:activityViewController error:outError]))
        return nil;
    
    _text = [[NSAttributedString alloc] init];
    _scale = 1;
    
    return self;
}

@synthesize text = _text;
- (void)setText:(NSAttributedString *)text;
{
    if (OFISEQUAL(_text, text))
        return;
    
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
    TextViewController *vc = [[TextViewController alloc] init];
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

    _viewControllerToPresent = nil;
    
    [super didClose];
}

+ (OUIImageLocation *)placeholderPreviewImageForFileURL:(NSURL *)fileURL area:(OUIDocumentPreviewArea)area;
{
    return [[OUIImageLocation alloc] initWithName:@"DocumentPreviewPlaceholder.png" bundle:[NSBundle mainBundle]];
}

#pragma mark -
#pragma mark UIDocument subclass

- (BOOL)readFromURL:(NSURL *)url error:(NSError **)outError;
{
    __autoreleasing NSDictionary *documentAttributes = nil;
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithURL:url options:@{} documentAttributes:&documentAttributes error:outError];
    if (!attributedString)
        return NO;
    
    NSNumber *scale = documentAttributes[NSViewZoomDocumentAttribute];
    if (scale != nil) {
        _scale = [scale floatValue] / 100;
        _scale = CLAMP(_scale, 0.25, 3.0);
    } else
        _scale = 1;
    
    // TODO: Make this all less RTF specific (now that NSAttributedString can do plain text, HTML, etc).
    NSLog(@"document attributes = %@", documentAttributes);
    
    _text = [attributedString copy];
    
    return YES;
}

- (NSString *)savingFileType;
{
    if (![NSString isEmptyString:_preferredSaveUTI]) {
        return _preferredSaveUTI;
    }
    
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

@end
