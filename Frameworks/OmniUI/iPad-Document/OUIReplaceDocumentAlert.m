// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIReplaceDocumentAlert.h>

#import <OmniDAV/ODAVFileInfo.h>

RCS_ID("$Id$")

// bug:///138501 (iOS-OmniGraffle Engineering: Fix OUIReplaceDocumentAlert depreciation warning)
@implementation OUIReplaceDocumentAlert
{
    __weak id <OUIReplaceDocumentAlertDelegate> _weak_delegate;
    NSURL *_documentURL;
}

- (id)initWithDelegate:(id <OUIReplaceDocumentAlertDelegate>)delegate documentURL:(NSURL *)aURL;
{
    if (!(self = [super init]))
        return nil;
    
    _weak_delegate = delegate;
    _documentURL = aURL;
    
    return self;
}


- (void)showFromViewController:(UIViewController *)presentingViewController;
{
    NSString *urlName = [ODAVFileInfo nameForURL:_documentURL];
    NSString *message = [NSString stringWithFormat: NSLocalizedStringFromTableInBundle(@"A document with the name \"%@\" already exists. Do you want to replace it? This cannot be undone.", @"OmniUIDocument", OMNI_BUNDLE, @"replace document description"), urlName];

    NSString *title = NSLocalizedStringFromTableInBundle(@"Replace document?", @"OmniUIDocument", OMNI_BUNDLE, @"replace document title");

    id <OUIReplaceDocumentAlertDelegate> delegate = _weak_delegate;

    UIAlertController *replaceDocumentController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];

    [replaceDocumentController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUIDocument", OMNI_BUNDLE, @"cancel button title") style:UIAlertActionStyleCancel handler:^(UIAlertAction * __nonnull action) {
        [delegate replaceDocumentAlert:self didDismissWithButtonIndex:0 documentURL:[_documentURL copy]];

    }]];
    [replaceDocumentController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Replace", @"OmniUIDocument", OMNI_BUNDLE, @"replace button title") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * __nonnull action) {
        [delegate replaceDocumentAlert:self didDismissWithButtonIndex:1 documentURL:[_documentURL copy]];

    }]];
    [replaceDocumentController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Rename",@"OmniUIDocument", OMNI_BUNDLE, @"rename button title") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {
        [delegate replaceDocumentAlert:self didDismissWithButtonIndex:2 documentURL:[_documentURL copy]];

    }]];

    [presentingViewController presentViewController:replaceDocumentController animated:YES completion:^{}];
}
     
@end
