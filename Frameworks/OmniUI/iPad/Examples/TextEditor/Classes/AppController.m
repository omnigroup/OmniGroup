// Copyright 2010-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "AppController.h"

#import "TextDocument.h"
#import "TextViewController.h"
#import "TextDocumentExporter.h"

#import <OmniUI/OUITextView.h>
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

- (Class)documentExporterClass
{
    return [TextDocumentExporter class];
}

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
    OBFinishPorting;
#if 0
    TextViewController *viewController = (TextViewController *)self.document.documentViewController;
    OUITextView *textView = viewController.textView;
    [textView inspectSelectedTextWithViewController:viewController fromBarButtonItem:item withSetupBlock:NULL]; // TODO: Use the setup block to scroll the selection to be visible while the inspector is up
#endif
}

#pragma mark - OUIAppController

#if 0
- (NSString *)aboutMenuTitle;
{
    return nil; // Hides the 'About' item in the gear menu
}
#endif

- (NSURL *)aboutScreenURL;
{
    return [NSURL URLWithString:@"data:"];
}

- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title modalPresentationStyle:(UIModalPresentationStyle)presentationStyle modalTransitionStyle:(UIModalTransitionStyle)transitionStyle animated:(BOOL)animated navigationBarHidden:(BOOL)navigationBarHidden;
{
    return nil;
}

- (void)showNewsInWindow:(nullable id)sender;
{
    // no op
}

+ (NSString *)openDocumentUserActivityType;
{
    return @"com.OmniGroup.TexEditor.OpenDocumentURLActivity";
}
+ (NSString *)createDocumentFromTemplateUserActivityType;
{
    return @"com.OmniGroup.TexEditor.CreateDocumentFromTemplateActivity";
}

#pragma mark - OUIAppController (InAppStore)

- (NSArray *)inAppPurchaseIdentifiers;
{
    return @[];
}

#pragma mark - OUIDocumentCreationRequestDelegate
- (NSString *)documentCreationRequestDocumentTypeForNewFiles:(nullable OUINewDocumentCreationRequest *)request;
{
    return (NSString *)kUTTypeRTF;
}

- (NSArray *)documentCreationRequestEditableDocumentTypes:(nullable OUINewDocumentCreationRequest *)request;
{
    return @[(NSString *)kUTTypeRTF];
}

- (NSArray<NSString *> *)templateUTIs;
{
    return @[(NSString *)kUTTypeRTF];
}

@end
