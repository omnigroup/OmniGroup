// Copyright 2010 The Omni Group.  All rights reserved.
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

- (void)dealloc;
{
    [_text release];
    [super dealloc];
}

@synthesize text = _text;

#pragma mark -
#pragma mark OUIDocument subclass

- (BOOL)loadDocumentContents:(NSError **)outError;
{
    if (self.proxy) {
        // Load existing document or use a template.
        NSString *rtfString = [[NSString alloc] initWithContentsOfURL:self.url encoding:NSUTF8StringEncoding error:outError];
        if (!rtfString)
            return NO;
        
        NSAttributedString *attributedString = [OUIRTFReader parseRTFString:rtfString];
        [rtfString release];
        
        if (!attributedString) {
            // TODO: Better handling
            OBFinishPorting;
        }
        
        _text = [[NSAttributedString alloc] initWithAttributedString:attributedString];
    } else {
        // New document
        _text = [[NSAttributedString alloc] init];
    }
    
    return YES;
}

- (UIViewController *)makeViewController;
{
    return [[[TextViewController alloc] initWithDocument:self] autorelease];
}

- (BOOL)saveToURL:(NSURL *)url isAutosave:(BOOL)isAutosave error:(NSError **)outError;
{
    // TODO: Ask the text editor to finish any edits/undo groups. Might be in the middle of marked text, for example.
    // TODO: Save a preview PDF somewhere.
    
    NSData *data = [OUIRTFWriter rtfDataForAttributedString:_text];
    return [data writeToURL:url options:0 error:outError];
}

@end
