// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OUIReplaceDocumentAlert;
@protocol OUIReplaceDocumentAlertDelegate
- (void)replaceDocumentAlert:(OUIReplaceDocumentAlert *)alert didDismissWithButtonIndex:(NSInteger)buttonIndex documentURL:(NSURL *)documentURL;
@end

@interface OUIReplaceDocumentAlert : OFObject <UIAlertViewDelegate>
{
@private
    id <OUIReplaceDocumentAlertDelegate> _nonretained_delegate;
    NSURL *_documentURL;
}
- (id)initWithDelegate:(id <OUIReplaceDocumentAlertDelegate>)delegate documentURL:(NSURL *)aURL;
- (void)show;
@end
