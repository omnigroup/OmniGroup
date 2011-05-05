// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class OFFileWrapper;
@class OUIDocumentPicker, OUIDocumentProxy;

#import <OmniUI/OUIDocumentProtocol.h>

@protocol OUIDocumentPickerDelegate <NSObject>
- (Class)documentPicker:(OUIDocumentPicker *)picker proxyClassForURL:(NSURL *)proxyURL;
- (NSString *)documentPickerBaseNameForNewFiles:(OUIDocumentPicker *)picker;
- (BOOL)createNewDocumentAtURL:(NSURL *)url error:(NSError **)outError;

@optional

- (NSString *)documentPickerDocumentTypeForNewFiles:(OUIDocumentPicker *)picker;

- (void)documentPicker:(OUIDocumentPicker *)picker scannedProxies:(NSSet *)proxies;

- (void)documentPicker:(OUIDocumentPicker *)picker didSelectProxy:(OUIDocumentProxy *)proxy;

// Export
- (NSArray *)documentPicker:(OUIDocumentPicker *)picker availableExportTypesForProxy:(OUIDocumentProxy *)proxy;
- (OFFileWrapper *)documentPicker:(OUIDocumentPicker *)picker exportFileWrapperOfType:(NSString *)fileType forProxy:(OUIDocumentProxy *)proxy error:(NSError **)outError;
- (BOOL)documentPicker:(OUIDocumentPicker *)picker canUseEmailBodyForType:(NSString *)fileType;

// Specific export types (for backwards compatibility)
- (NSData *)documentPicker:(OUIDocumentPicker *)picker PDFDataForProxy:(OUIDocumentProxy *)proxy error:(NSError **)outError;
- (NSData *)documentPicker:(OUIDocumentPicker *)picker PNGDataForProxy:(OUIDocumentProxy *)proxy error:(NSError **)outError;

// For the export button. If implemented, a 'Send to Camera Roll' item will be in the menu. Can return nil to have a default implementation of using the document's preview, scaled to fit the current device orientation.
- (UIImage *)documentPicker:(OUIDocumentPicker *)picker cameraRollImageForProxy:(OUIDocumentProxy *)proxy;

// On the iPad, it won't let you show the print panel form a sheet, so we go from the action sheet to another popover
- (void)documentPicker:(OUIDocumentPicker *)picker printProxy:(OUIDocumentProxy *)proxy fromButton:(UIButton *)aButton;

// Title of the print button in the action menu
- (NSString *)documentPicker:(OUIDocumentPicker *)picker printButtonTitleForProxy:(OUIDocumentProxy *)proxy;

// Hook for custom export options
- (void)documentPicker:(OUIDocumentPicker *)picker addExportActionsToSheet:(UIActionSheet *)actionSheet invocations:(NSMutableArray *)invocations;

- (UIImage *)documentPicker:(OUIDocumentPicker *)picker iconForUTI:(CFStringRef)fileUTI;        // used by the export file browser
- (UIImage *)documentPicker:(OUIDocumentPicker *)picker exportIconForUTI:(CFStringRef)fileUTI;  // used by the large export options buttons
- (NSString *)documentPicker:(OUIDocumentPicker *)picker labelForUTI:(CFStringRef)fileUTI;

@end
