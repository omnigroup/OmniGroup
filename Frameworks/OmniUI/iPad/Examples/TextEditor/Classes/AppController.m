// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "AppController.h"

#import "RTFDocument.h"
#import "TextViewController.h"

#import <OmniUI/OUIEditableFrame.h>
#import <OmniUI/OUITextLayout.h>
#import <MobileCoreServices/MobileCoreServices.h>

RCS_ID("$Id$")

@implementation AppController
{
    NSArray *_documentToolbarItems;
}

+ (void)initialize;
{
    OBINITIALIZE;

    CFDictionaryRef type = UTTypeCopyDeclaration(kUTTypeRTF);
    NSLog(@"rtf = %@", type);
    if (type)
        CFRelease(type);
}

#pragma mark -
#pragma mark OUISingleDocumentAppController subclass

- (Class)documentClassForURL:(NSURL *)url;
{
    // TODO: check the UTI of the incoming URL
    return [RTFDocument class];
}

- (UIView *)pickerAnimationViewForTarget:(OUIDocument *)document;
{
    return ((TextViewController *)document.viewController).scrollView;
}

- (NSArray *)toolbarItemsForDocument:(OUIDocument *)document;
{
    // Cache document toolbar items. These must *only* target the given object (not the document) so that we can reuse them.
    if (!_documentToolbarItems) {
        NSMutableArray *items = [NSMutableArray array];
        
        [items addObject:self.closeDocumentBarButtonItem];
        
        [items addObject:self.undoBarButtonItem];
        
        [items addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
        
        UIBarButtonItem *omniPresenceBarButtonItem = [self.document omniPresenceBarButtonItem];
        if (omniPresenceBarButtonItem != nil)
            [items addObject:omniPresenceBarButtonItem];

        [items addObject:self.documentTitleToolbarItem];
        
        [items addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
        
        [items addObject:self.infoBarButtonItem];

        UIBarButtonItem *attachImageButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCamera target:nil action:@selector(attachImage:)] autorelease];

        [items addObject:attachImageButtonItem];
        
        _documentToolbarItems = [[NSArray alloc] initWithArray:items];
    }
    
    return _documentToolbarItems;
}

- (NSString *)feedbackMenuTitle;
{
    return @"Help";
}

- (void)showInspectorFromBarButtonItem:(UIBarButtonItem *)item;
{
    OUIEditableFrame *editor = ((TextViewController *)self.document.viewController).editor;
    [editor inspectSelectedTextFromBarButtonItem:item];
}

#pragma mark -
#pragma mark OFSDocumentStoreDelegate

- (NSString *)documentStoreDocumentTypeForNewFiles:(OFSDocumentStore *)store;
{
    return (NSString *)kUTTypeRTF;
}

#pragma mark -
#pragma mark OUIDocumentPickerDelegate

- (NSData *)documentPicker:(OUIDocumentPicker *)picker PDFDataForFileItem:(OFSDocumentStoreFileItem *)fileItem error:(NSError **)outError;
{
    RTFDocument *doc = [[RTFDocument alloc] initWithExistingFileItem:fileItem error:outError];
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
    [doc willClose];
    [doc release];
    
    return data;
}

@end
