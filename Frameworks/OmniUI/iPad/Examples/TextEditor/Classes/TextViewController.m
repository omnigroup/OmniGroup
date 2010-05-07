// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "TextViewController.h"

#import <OmniUI/OUIEditableFrame.h>

#import "RTFDocument.h"

RCS_ID("$Id$");

@implementation TextViewController

- initWithDocument:(RTFDocument *)document;
{
    if (!(self = [super initWithNibName:@"TextViewController" bundle:nil]))
        return nil;
    
    _nonretained_document = document;
    
    return self;
}

- (void)dealloc;
{
    [_editor release];
    [super dealloc];
}

@synthesize editor = _editor;

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];

    _editor.delegate = self;
    _editor.attributedText = _nonretained_document.text;
}

- (void)viewDidUnload;
{
    self.editor = nil;
    [super viewDidUnload];
}

#pragma mark OUIEditableFrameDelegate

- (void)textViewDidEndEditing:(OUIEditableFrame *)textView;
{
    // We need more of a text storage model so that selection changes can participate in undo.
    _nonretained_document.text = textView.attributedText;
}

@end
