// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "RTFDocument.h"

#import <OmniUI/OUIRTFReader.h>
#import <OmniUI/OUIRTFWriter.h>

#import "TextViewController.h"

RCS_ID("$Id$");

@implementation RTFDocument
{
    NSAttributedString *_text;
}

- initEmptyDocumentToBeSavedToURL:(NSURL *)url error:(NSError **)outError;
{
    if (!(self = [super initEmptyDocumentToBeSavedToURL:url error:outError]))
        return nil;
    
    _text = [[NSAttributedString alloc] init];
    
    return self;
}

- (void)dealloc;
{
    [_text release];
    [super dealloc];
}

@synthesize text = _text;
- (void)setText:(NSAttributedString *)text;
{
    if (OFISEQUAL(_text, text))
        return;
    
    [_text release];
    _text = [text copy];
    
    // We don't support undo right now, but at least poke the UIDocument autosave timer.
    [self updateChangeCount:UIDocumentChangeDone];
}

#pragma mark -
#pragma mark OUIDocument subclass

- (UIViewController *)makeViewController;
{
    return [[[TextViewController alloc] init] autorelease];
}

+ (UIImage *)placeholderPreviewImageForFileItem:(OUIDocumentStoreFileItem *)item landscape:(BOOL)landscape;
{
    return [UIImage imageNamed:@"DocumentPreviewPlaceholder.png"];
}

+ (BOOL)writePreviewsForDocument:(OUIDocument *)document error:(NSError **)outError;
{
    OBUserCancelledError(outError);
    return NO;
}

#pragma mark -
#pragma mark UIDocument subclass

- (BOOL)readFromURL:(NSURL *)url error:(NSError **)outError;
{    
    NSString *rtfString = [[NSString alloc] initWithContentsOfURL:url encoding:NSUTF8StringEncoding error:outError];
    if (!rtfString)
        return NO;
    
    NSAttributedString *attributedString = [OUIRTFReader parseRTFString:rtfString];
    [rtfString release];
    
    if (!attributedString) {
        // TODO: Better handling
        OBFinishPorting;
    }
    
    [_text release];
    _text = [attributedString copy];
    
    return YES;
}

- (BOOL)writeContents:(id)contents toURL:(NSURL *)url forSaveOperation:(UIDocumentSaveOperation)saveOperation originalContentsURL:(NSURL *)originalContentsURL error:(NSError **)outError;
{
    // TODO: Ask the text editor to finish any edits/undo groups. Might be in the middle of marked text, for example.
    // TODO: Save a preview PDF somewhere.
    
    NSData *data = [OUIRTFWriter rtfDataForAttributedString:_text];
    return [data writeToURL:url options:0 error:outError];
}

@end
