// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class OUIDocumentPicker, OUIDocumentProxy;

#import <OmniUI/OUIDocumentProtocol.h>

@protocol OUIDocumentPickerDelegate <NSObject>
- (Class)documentPicker:(OUIDocumentPicker *)picker proxyClassForURL:(NSURL *)proxyURL;
- (NSString *)documentPickerBaseNameForNewFiles:(OUIDocumentPicker *)picker;
- (NSString *)documentPickerDocumentTypeForNewFiles:(OUIDocumentPicker *)picker;
- (id <OUIDocument>)createNewDocumentAtURL:(NSURL *)url error:(NSError **)outError;

@optional

- (void)documentPicker:(OUIDocumentPicker *)picker scannedProxies:(NSSet *)proxies;

- (void)documentPicker:(OUIDocumentPicker *)picker didSelectProxy:(OUIDocumentProxy *)proxy;

// For the export button. We could potentially use +getPDFPreviewData:... by default, but we probably want a multi-page PDF document in OmniGraffle.
- (NSData *)documentPicker:(OUIDocumentPicker *)picker PDFDataForProxy:(OUIDocumentProxy *)proxy error:(NSError **)outError;
- (NSData *)documentPicker:(OUIDocumentPicker *)picker PNGDataForProxy:(OUIDocumentProxy *)proxy error:(NSError **)outError;

// For the export button. If implemented, a 'Send to Camera Roll' item will be in the menu. Can return nil to have a default implementation of using the document's preview, scaled to fit the current device orientation.
- (UIImage *)documentPicker:(OUIDocumentPicker *)picker cameraRollImageForProxy:(OUIDocumentProxy *)proxy;

@end
