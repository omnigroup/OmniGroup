// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "TextDocumentExporter.h"

#import "TextDocument.h"

#import <OmniUI/OUITextLayout.h>

RCS_ID("$Id$")

@implementation TextDocumentExporter

- (UIImage *)exportIconForUTI:(NSString *)fileUTI;
{
    // This should really handle PDF and such too.
    return [UIImage imageNamed:@"Text"];
}

//- (NSData *)PDFDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;
//{
//    OBFinishPorting;
//#if 0
//    TextDocument *doc = [[TextDocument alloc] initWithExistingFileItem:fileItem error:outError];
//    if (!doc)
//        return nil;
//
//    // TODO: Paper sizes, pagination
//    const CGFloat pdfWidth = 500;
//
//    OUITextLayout *textLayout = [[OUITextLayout alloc] initWithAttributedString:doc.text constraints:CGSizeMake(pdfWidth, 0)];
//
//    CGRect bounds = CGRectMake(0, 0, pdfWidth, [textLayout usedSize].height);
//    NSMutableData *data = [NSMutableData data];
//
//    NSMutableDictionary *documentInfo = [NSMutableDictionary dictionary];
//    NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleNameKey];
//    if (appName)
//        [documentInfo setObject:appName forKey:(id)kCGPDFContextCreator];
//
//    // other keys we might want to add
//    // kCGPDFContextAuthor - string
//    // kCGPDFContextSubject -- string
//    // kCGPDFContextKeywords -- string or array of strings
//    UIGraphicsBeginPDFContextToData(data, bounds, documentInfo);
//    {
//        CGContextRef ctx = UIGraphicsGetCurrentContext();
//
//        UIGraphicsBeginPDFPage();
//
//        [textLayout drawFlippedInContext:ctx bounds:bounds];
//    }
//    UIGraphicsEndPDFContext();
//
//    [textLayout release];
//    [doc didClose];
//    [doc release];
//
//    return data;
//#endif
//}

@end
