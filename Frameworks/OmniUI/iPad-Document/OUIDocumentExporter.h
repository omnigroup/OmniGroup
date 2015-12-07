// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@import MessageUI;
@import Foundation;
@import OmniDocumentStore;
@import OmniUnzip;

#import <OmniUIDocument/OUIDocumentPicker.h>

@protocol OUIDocumentExporterHost <NSObject>

- (ODSFileItem *)fileItemToExport;
- (UIColor *)tintColorForExportMenu;

@optional
- (void)prepareToExport;

@end

/// Create instances using the +exporterForViewController method instead of -init
@interface OUIDocumentExporter : NSObject <MFMailComposeViewControllerDelegate>

@property (nonatomic, weak) UIViewController <OUIDocumentExporterHost> *hostViewController;
@property (nonatomic, strong) UIBarButtonItem *barButtonItem;

+ (instancetype)exporterForViewController:(UIViewController<OUIDocumentExporterHost> *)hostViewController;
+ (void)clearOpenInCache;

- (BOOL)canExportFileItem:(ODSFileItem *)fileItem;
- (void)exportItem:(ODSFileItem *)fileItem;
- (void)export:(id)sender;
- (void)emailFileItem:(ODSFileItem *)fileItem;
- (void)sendEmailWithFileWrapper:(NSFileWrapper *)fileWrapper forExportType:(NSString *)exportType fileName:(NSString *)fileName;
- (void)clearSelection;
- (NSArray *)availableExportTypesForFileItem:(ODSFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType;

#pragma mark - Possible Subclass Overrides
- (UIImage *)iconForUTI:(NSString *)fileUTI;
- (UIImage *)exportIconForUTI:(NSString *)fileUTI;
- (NSString *)exportLabelForUTI:(NSString *)fileUTI;
- (void)exportFileWrapperOfType:(NSString *)exportType forFileItem:(ODSFileItem *)fileItem withCompletionHandler:(void (^)(NSFileWrapper *fileWrapper, NSError *error))completionHandler;
- (BOOL)_canUseEmailBodyForExportType:(NSString *)exportType;
- (NSArray<OUIMenuOption *> *)additionalExportOptionsForFileItem:(ODSFileItem *)fileItem;
- (NSMutableArray *)appSpecificAvailableExportTypesForFileItem:(ODSFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType;
- (BOOL)supportsSendToCameraRoll;
- (BOOL)supportsPrinting;
- (BOOL)supportsCopyAsImage;
- (BOOL)supportsExportAsPDF;
- (BOOL)supportsExportAsPNG;
- (NSArray *)availableInAppPurchaseExportTypesForFileItem:(ODSFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType;
- (NSString *)printButtonTitleForFileItem:(ODSFileItem *)fileItem;
- (void)printFileItem:(ODSFileItem *)fileItem fromButton:(UIBarButtonItem *)aButton;
- (NSData *)copyAsImageDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;
- (UIImage *)cameraRollImageForFileItem:(ODSFileItem *)fileItem;
- (NSData *)PDFDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)error;
- (NSData *)PNGDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)error;
- (void)purchaseExportType:(NSString *)fileUTI navigationController:(UINavigationController *)navigationController;  // not sure we should really have the navigation controller here.  it might need to just be generic view controller (our hostController).  also, it might turn out this can be implemented on the superclass instead of the subclasses.
- (NSString *)purchaseDescriptionForExportType:(NSString *)fileUTI;

@end
