// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIReplaceDocumentAlert.h>

#import <OmniFileStore/OFSFileInfo.h>

RCS_ID("$Id$")

@implementation OUIReplaceDocumentAlert

- (id)initWithDelegate:(id <OUIReplaceDocumentAlertDelegate>)delegate documentURL:(NSURL *)aURL;
{
    if (!(self = [super init]))
        return nil;
    
    _nonretained_delegate = delegate;
    _documentURL = [aURL retain];
    
    return self;
}

- (void)dealloc;
{
    [_documentURL release];
    
    [super dealloc];
}

- (void)show;
{
    NSString *urlName = [OFSFileInfo nameForURL:_documentURL];
    NSString *message = [NSString stringWithFormat: NSLocalizedStringFromTableInBundle(@"A document with the name \"%@\" already exists. Do you want to replace it? This cannot be undone.", @"OmniUI", OMNI_BUNDLE, @"replace document description"), urlName];
    UIAlertView *replaceDocumentAlert = [[UIAlertView alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Replace document?", @"OmniUI", OMNI_BUNDLE, @"replace document title") message:message delegate:self cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"cancel button title") otherButtonTitles:NSLocalizedStringFromTableInBundle(@"Replace", @"OmniUI", OMNI_BUNDLE, @"replace button title"), NSLocalizedStringFromTableInBundle(@"Rename",@"OmniUI", OMNI_BUNDLE, @"rename button title"), nil];
    [replaceDocumentAlert show];
    [replaceDocumentAlert release];
}

#pragma mark -
#pragma mark UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex;
{
    [_nonretained_delegate replaceDocumentAlert:self didDismissWithButtonIndex:buttonIndex documentURL:[[_documentURL copy] autorelease]];
}
     
@end
