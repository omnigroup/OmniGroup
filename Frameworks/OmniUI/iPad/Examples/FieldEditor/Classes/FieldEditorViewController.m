// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "FieldEditorViewController.h"

#import <OmniUI/OUIRTFReader.h>
#import <OmniUI/OUIEditableFrame.h>

#import <QuartzCore/QuartzCore.h>
#import "TextLayoutView.h"

RCS_ID("$Id$")

@implementation FieldEditorViewController

- (void)dealloc;
{
    [_textLayoutView release];
    [_text release];
    [super dealloc];
}

#pragma mark -
#pragma mark UIViewController subclass

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    return YES;
}

- (void)viewDidLoad;
{
    NSString *rtfPath = [[NSBundle mainBundle] pathForResource:@"Text" ofType:@"rtf"];
    
    NSError *error = nil;
    NSString *rtfString = [[NSString alloc] initWithContentsOfURL:[NSURL fileURLWithPath:rtfPath] encoding:NSUTF8StringEncoding error:&error];
    if (!rtfString) {
        NSLog(@"Unable to load RTF: %@", [error toPropertyList]);
        return;
    }

    _text = [[OUIRTFReader parseRTFString:rtfString] copy];
    [rtfString release];
    
    CGRect textRect = CGRectMake(40, 100, 200, 200);
    
    _textLayoutView = [[TextLayoutView alloc] initWithFrame:textRect];
    _textLayoutView.layer.borderColor = [[UIColor colorWithRed:0.75 green:0.75 blue:1.0 alpha:1.0] CGColor];
    _textLayoutView.layer.borderWidth = 1;
    _textLayoutView.text = _text;

    _editableFrame = [[OUIEditableFrame alloc] initWithFrame:textRect];
    _editableFrame.backgroundColor = [UIColor whiteColor];
    _editableFrame.layer.borderColor = [[UIColor colorWithRed:0.25 green:0.25 blue:1.0 alpha:1.0] CGColor];
    _editableFrame.layer.borderWidth = 1;
    _editableFrame.attributedText = _text;
    
    [self.view addSubview:_textLayoutView];
}

- (void)viewDidUnload;
{
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (IBAction)toggleEditor:(id)sender;
{
    if ([(UISegmentedControl *)sender selectedSegmentIndex] == 0) {
        [self.view addSubview:_textLayoutView];
        [_editableFrame removeFromSuperview];
    } else {
        [_textLayoutView removeFromSuperview];
        [self.view addSubview:_editableFrame];
    }
}

@end
