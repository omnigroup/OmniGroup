// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "AppController.h"

#import "RTFDocument.h"
#import "TextViewController.h"

#import <OmniUI/OUIEditableFrame.h>
#import <MobileCoreServices/MobileCoreServices.h>

RCS_ID("$Id$")

@implementation AppController

+ (void)initialize;
{
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
    return ((TextViewController *)document.viewController).editor;
}

- (NSArray *)toolbarItemsForDocument:(OUIDocument *)document;
{
    // Cache document toolbar items. These must *only* target the given object (not the document) so that we can reuse them.
    if (!_documentToolbarItems) {
        NSMutableArray *items = [NSMutableArray array];
        
        [items addObject:self.closeDocumentBarButtonItem];
        
        [items addObject:self.undoBarButtonItem];
        
        [items addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
        
        [items addObject:self.documentTitleToolbarItem];
        
        [items addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
                
        _documentToolbarItems = [[NSArray alloc] initWithArray:items];
    }
    
    return _documentToolbarItems;
}

- (void)dismissInspectorImmediately;
{
    // No inspector toolbar item right now
}

#pragma mark -
#pragma mark OUIDocumentPickerDelegate

- (NSString *)documentPickerDocumentTypeForNewFiles:(OUIDocumentPicker *)picker;
{
    return (NSString *)kUTTypeRTF;
}

@end
