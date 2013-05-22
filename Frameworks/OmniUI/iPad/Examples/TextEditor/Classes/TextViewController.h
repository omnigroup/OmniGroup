// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIScalingViewController.h>
#import <OmniUI/OUIEditableFrameDelegate.h>
#import <OmniUIDocument/OUIDocumentViewController.h>

@class RTFDocument;
@class OUIEditableFrame;

@interface TextViewController : OUIScalingViewController <OUIDocumentViewController, OUIEditableFrameDelegate>

@property(retain,nonatomic) IBOutlet UIToolbar *toolbar;
@property(retain,nonatomic) IBOutlet OUIEditableFrame *editor;

@property(nonatomic) BOOL forPreviewGeneration;

@end
