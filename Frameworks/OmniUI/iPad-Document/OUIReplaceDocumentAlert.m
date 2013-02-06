// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIReplaceDocumentAlert.h>

#import <OmniFileStore/OFSFileInfo.h>

RCS_ID("$Id$")

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


- (void)show;
{
    NSString *urlName = [OFSFileInfo nameForURL:_documentURL];
    NSString *message = [NSString stringWithFormat: NSLocalizedStringFromTableInBundle(@"A document with the name \"%@\" already exists. Do you want to replace it? This cannot be undone.", @"OmniUIDocument", OMNI_BUNDLE, @"replace document description"), urlName];
    UIAlertView *replaceDocumentAlert = [[UIAlertView alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Replace document?", @"OmniUIDocument", OMNI_BUNDLE, @"replace document title") message:message delegate:self cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUIDocument", OMNI_BUNDLE, @"cancel button title") otherButtonTitles:NSLocalizedStringFromTableInBundle(@"Replace", @"OmniUIDocument", OMNI_BUNDLE, @"replace button title"), NSLocalizedStringFromTableInBundle(@"Rename",@"OmniUIDocument", OMNI_BUNDLE, @"rename button title"), nil];
    [replaceDocumentAlert show];
}

#pragma mark -
#pragma mark UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex;
{
    id <OUIReplaceDocumentAlertDelegate> delegate = _weak_delegate;

    [delegate replaceDocumentAlert:self didDismissWithButtonIndex:buttonIndex documentURL:[_documentURL copy]];
}
     
@end
