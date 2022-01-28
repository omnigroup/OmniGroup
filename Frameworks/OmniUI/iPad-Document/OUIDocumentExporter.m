// Copyright 2015-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentExporter.h>

@import MobileCoreServices;
@import OmniBase;
@import OmniFileExchange;
@import OmniFoundation;
@import OmniUI;
@import Photos;
@import UniformTypeIdentifiers.UTCoreTypes;

#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIErrors.h>
#import <OmniUIDocument/OmniUIDocument-Swift.h>

#import "OUIExportOptionsController.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OUIDocumentExporter

+ (instancetype)exporter;
{
    OUIDocumentAppController *appDelegate = OB_CHECKED_CAST(OUIDocumentAppController, [[UIApplication sharedApplication] delegate]);
    return [[[appDelegate documentExporterClass] alloc] init];
}

- (UIBarButtonItem *)makeExportBarButtonItemWithTarget:(id)target action:(SEL)action forViewController:(UIViewController *)viewController;
{
    UIImage *image = [[OUIAppController controller] exportBarButtonItemImageInViewController:viewController];

    UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain target:target action:action];
    barButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Export", @"OmniUIDocument", OMNI_BUNDLE, @"Export toolbar item accessibility label.");
    barButtonItem.image = image; // compactness might have changed

    return barButtonItem;
}

- (void)exportDocument:(OUIDocument *)document fromViewController:(UIViewController *)parentViewController barButtonItem:(UIBarButtonItem *)exportBarButtonItem;
{
    NSURL *fileURL = document.fileURL;
    
    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL, document] applicationActivities:self.supportedActivities];
    
    activityViewController.modalPresentationStyle = UIModalPresentationPopover;
    activityViewController.popoverPresentationController.barButtonItem = exportBarButtonItem;
    
    activityViewController.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *errorOrNil){
        if (errorOrNil) {
            [OUIAppController presentError:errorOrNil fromViewController:parentViewController];
        }
    };
    
    [parentViewController presentViewController:activityViewController animated:YES completion:nil];
}

- (NSArray <UIActivity *> *)supportedActivities;
{
    NSMutableArray <UIActivity *> *activities = [NSMutableArray array];
    
    // This should be all the supported activities -- each activity will be able to decide whether it applies once it gets the input items.
    [activities addObject:[self makeShareAsActivity]];
    [activities addObject:[self makeCopyAsImageActivity]];
    [activities addObject:[self makeSendToPhotosActivity]];
    [activities addObject:[self makePrintActivity]];

    return activities;
}

static BOOL DocumentClassSubclasses(Class cls, SEL sel) {
    Class implementing = OBClassImplementingMethod(cls, sel);
    OBASSERT(implementing);
    return implementing != [OUIDocument class];
}

- (NSArray *)availableExportTypesForFileURL:(NSURL *)fileURL
{
    Class documentClass = [[OUIDocumentAppController controller] documentClassForURL:fileURL];
    NSError *fileTypeError;
    NSString *fileType = OFUTIForFileURLPreferringNative(fileURL, &fileTypeError);
    if (!fileType) {
        [fileTypeError log:@"Error determining file type for %@", fileURL];
        return nil;
    }
    
    NSMutableArray *exportTypes = [[documentClass availableExportTypesForFileType:fileType isFileExportToLocalDocuments:NO] mutableCopy];
    if (!exportTypes) {
        exportTypes = [NSMutableArray array];
        
        // Add the 'native' marker
        [exportTypes insertObject:[NSNull null] atIndex:0];
        
        // PNG Fallbacks
        BOOL canMakePNG = DocumentClassSubclasses(documentClass, @selector(PNGData:));
        if (canMakePNG)
            [exportTypes addObject:(NSString *)kUTTypePNG];
    }
    
    return exportTypes;
}

#pragma mark - Subclass Overrides

- (nullable UIImage *)iconForUTI:(NSString *)fileUTI;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (nullable UIImage *)exportIconForUTI:(NSString *)fileUTI;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (nullable NSString *)exportLabelForUTI:(NSString *)fileUTI;
{
    if (OFTypeConformsTo(fileUTI, UTTypePDF))
        return @"PDF";
    if (OFTypeConformsTo(fileUTI, UTTypePNG))
        return @"PNG";
    if (OFTypeConformsTo(fileUTI, UTTypeSVG))
        return @"SVG";
    return nil;
}

+ (UIImage *)sendToPasteboardImage;
{
    return [UIImage imageNamed:@"OUIMenuItemCopyAsImage" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}
+ (UIImage *)copyAsImageImage;
{
    return [UIImage imageNamed:@"OUIMenuItemCopyAsImage" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}
+ (UIImage *)sendToPhotosImage;
{
    return [UIImage imageNamed:@"OUIMenuItemSendToPhotos" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

- (NSArray *)availableInAppPurchaseExportTypesForFileURL:(NSURL *)fileURL;
{
    NSMutableArray *exportTypes = [NSMutableArray array];
    return exportTypes;
}

- (void)purchaseExportType:(NSString *)fileUTI scene:(UIScene *)scene;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSString *)purchaseDescriptionForExportType:(NSString *)fileUTI;
{
    OBRequestConcreteImplementation(self, _cmd);
}

@end


@implementation OUIDocument (OUIDocumentExporter)

- (nullable NSData *)PNGData:(NSError **)outError;
{
    OBASSERT_NOT_REACHED("Should be called on subclass");
    OBUserCancelledError(outError);
    return nil;
}

- (nullable UIImage *)cameraRolImage:(NSError **)outError;
{
    OBASSERT_NOT_REACHED("Should be called on subclass");
    OBUserCancelledError(outError);
    return nil;
}

- (void)printWithParentViewController:(UIViewController *)parentViewController completionHandler:(void (^)(NSError * _Nullable errorOrNil))completionHandler;
{
    OBASSERT_NOT_REACHED("Should be called on subclass");
    __autoreleasing NSError *error;
    OBUserCancelledError(&error);
    completionHandler(error);
}

- (void)exportFileWrapperOfType:(NSString *)exportType parentViewController:(UIViewController *)parentViewController withCompletionHandler:(void (^)(NSFileWrapper * _Nullable fileWrapper, NSError * _Nullable error))completionHandler;
{
    OBASSERT_NOTNULL(completionHandler);
    

    completionHandler = [completionHandler copy]; // preserve scope

    NSURL *fileURL = self.fileURL;
    NSString *existingType = self.fileType;
        
    // For 'native' files, don't bother with loading in all the data, just grab the file wrapper
    if (OFISNULL(exportType) || [exportType isEqual:existingType]) {
        // The 'nil' type is always first in our list of types, so we can eport the original file as is w/o going through any app specific exporter.
        // NOTE: This is important for OO3 where the exporter has the ability to rewrite the document w/o hidden columns, in sorted order, with summary values (and eventually maybe with filtering). If we want to support untransformed exporting through the OO XML exporter, it will need to be configurable via settings on the OOXSLPlugin it uses. For now it assumes all 'exports' want all the transformations.

        [NSFileCoordinator readFileWrapperAtFileURL:fileURL completionHandler:^(NSFileWrapper *fileWrapper, NSError *errorOrNil) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                completionHandler(fileWrapper, errorOrNil);
            }];
        }];
        return;
    }

    // Default support for document subclasses that implement other exporting methods.
    __autoreleasing NSError *error = nil;
    NSData *fileData = nil;
    
    if (OFTypeConformsTo(exportType, UTTypePNG) && DocumentClassSubclasses([self class], @selector(PNGData:))) {
        fileData = [self PNGData:&error];
    } else {
        OBASSERT_NOT_REACHED("Should not have specified we can export a type w/o handling it");
        OBUserCancelledError(&error);
    }

    if (!fileData) {
        completionHandler(nil, error);
        return;
    }
    
    NSString *pathExtension = OFPreferredFilenameExtensionForTypePreferringNative(exportType);
    
    NSFileWrapper *fileWrapper = [[NSFileWrapper alloc] initRegularFileWithContents:fileData];
    fileWrapper.preferredFilename = [self.name stringByAppendingPathExtension:pathExtension];
    
    completionHandler(fileWrapper, error);
}

@end

NS_ASSUME_NONNULL_END

