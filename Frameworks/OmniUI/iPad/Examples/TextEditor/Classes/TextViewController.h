// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIScalingViewController.h>
#import <OmniUI/OUIEditableFrameDelegate.h>

@class RTFDocument;
@class OUIEditableFrame;

@interface TextViewController : OUIScalingViewController <OUIEditableFrameDelegate>
{
@private
    RTFDocument *_nonretained_document;
    OUIEditableFrame *_editor;
}

- initWithDocument:(RTFDocument *)document;

@property(retain,nonatomic) IBOutlet OUIEditableFrame *editor;

@end
