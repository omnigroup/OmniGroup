// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "AppController.h"

#import "TextDocument.h"
#import "TextViewController.h"

#import <OmniUI/OUITextView.h>
#import <OmniUI/OUITextLayout.h>
#import <MobileCoreServices/MobileCoreServices.h>

RCS_ID("$Id$")

@implementation AppController

+ (void)initialize;
{
    OBINITIALIZE;
    
    // For setting up our UTImportedTypeDeclarations...
    for (NSString *type in @[(OB_BRIDGE id)kUTTypeRTF, (OB_BRIDGE id)kUTTypeRTFD, (OB_BRIDGE id)kUTTypePlainText]) {
        CFDictionaryRef declaration = UTTypeCopyDeclaration((OB_BRIDGE CFStringRef)type);
        NSLog(@"%@ = %@", type, declaration);
        if (declaration)
            CFRelease(declaration);
    }
}

#pragma mark - OUISingleDocumentAppController subclass

- (Class)documentClassForURL:(NSURL *)url;
{
    // TODO: check that the UTI of the incoming URL is somethign we can handle
    return [TextDocument class];
}

- (UIView *)pickerAnimationViewForTarget:(OUIDocument *)document;
{
    return ((TextViewController *)document.documentViewController).textView;
}

- (NSString *)feedbackMenuTitle;
{
    return @"Help";
}

- (void)showInspectorFromBarButtonItem:(UIBarButtonItem *)item;
{
    TextViewController *viewController = (TextViewController *)self.document.documentViewController;
    OUITextView *textView = viewController.textView;
    [textView inspectSelectedTextWithViewController:viewController fromBarButtonItem:item withSetupBlock:NULL]; // TODO: Use the setup block to scroll the selection to be visible while the inspector is up
}

#pragma mark - OUIAppController

- (NSString *)aboutMenuTitle;
{
    return nil; // Hides the 'About' item in the gear menu
}

#pragma mark - OUIAppController (InAppStore)

- (NSArray *)inAppPurchaseIdentifiers;
{
    return @[];
}

#pragma mark - ODSStoreDelegate

- (NSString *)documentStoreDocumentTypeForNewFiles:(ODSStore *)store;
{
    return (NSString *)kUTTypeRTF;
}

#pragma mark - OUIDocumentPickerDelegate

- (NSData *)documentPicker:(OUIDocumentPicker *)picker PDFDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;
{
    TextDocument *doc = [[TextDocument alloc] initWithExistingFileItem:fileItem error:outError];
    if (!doc)
        return nil;
    
    // TODO: Paper sizes, pagination
    const CGFloat pdfWidth = 500;
    
    OUITextLayout *textLayout = [[OUITextLayout alloc] initWithAttributedString:doc.text constraints:CGSizeMake(pdfWidth, 0)];
    
    CGRect bounds = CGRectMake(0, 0, pdfWidth, [textLayout usedSize].height);
    NSMutableData *data = [NSMutableData data];
    
    NSMutableDictionary *documentInfo = [NSMutableDictionary dictionary];
    NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleNameKey];
    if (appName)
        [documentInfo setObject:appName forKey:(id)kCGPDFContextCreator];

    // other keys we might want to add
    // kCGPDFContextAuthor - string
    // kCGPDFContextSubject -- string
    // kCGPDFContextKeywords -- string or array of strings
    UIGraphicsBeginPDFContextToData(data, bounds, documentInfo);
    {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        
        UIGraphicsBeginPDFPage();
        
        [textLayout drawFlippedInContext:ctx bounds:bounds];
    }
    UIGraphicsEndPDFContext();
    
    [textLayout release];
    [doc didClose];
    [doc release];
    
    return data;
}

@end
