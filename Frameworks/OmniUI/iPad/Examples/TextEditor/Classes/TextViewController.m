// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "TextViewController.h"

#import <OmniUI/OUIEditableFrame.h>
#import <QuartzCore/QuartzCore.h>

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
#pragma mark UIResponder subclass

- (NSUndoManager *)undoManager;
{
    // Make sure we get the document's undo manager, not an implicitly created one from UIWindow!
    return [_nonretained_document undoManager];
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];

#if 0
    self.view.layer.borderColor = [[UIColor blueColor] CGColor];
    self.view.layer.borderWidth = 2;
    
    _editor.layer.borderColor = [[UIColor colorWithRed:0.75 green:0.75 blue:1.0 alpha:1.0] CGColor];
    _editor.layer.borderWidth = 2;
#endif
    
    _editor.textInset = UIEdgeInsetsMake(4, 4, 4, 4);
    _editor.delegate = self;
    
    _editor.attributedText = _nonretained_document.text;
    [self textViewContentsChanged:_editor];
    
    [self adjustScaleTo:1];
    [self adjustContentInset];
}

- (void)viewDidUnload;
{
    self.editor = nil;
    [super viewDidUnload];
}

#pragma mark OUIEditableFrameDelegate

static CGFloat kPageWidth = (72*8.5); // Vaguely something like 8.5x11 width.

- (void)textViewContentsChanged:(OUIEditableFrame *)textView;
{
    CGFloat usedHeight = _editor.viewUsedSize.height;
    _editor.frame = CGRectMake(0, 0, kPageWidth, usedHeight);
}

- (void)textViewDidEndEditing:(OUIEditableFrame *)textView;
{
    // We need more of a text storage model so that selection changes can participate in undo.
    _nonretained_document.text = textView.attributedText;
}

#pragma mark -
#pragma mark OUIScalingViewController subclass

- (CGSize)canvasSize;
{
    if (!_editor)
        return CGSizeZero; // Don't know our canvas size yet. We'll set up initial scaling in -viewDidLoad.
    
    CGSize size;
    size.width = kPageWidth;
    size.height = _editor.textUsedSize.height;

    return size;
}

#pragma mark -
#pragma mark UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView;
{
    return _editor;
}

@end
