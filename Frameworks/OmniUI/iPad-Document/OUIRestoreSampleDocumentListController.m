// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIRestoreSampleDocumentListController.h"

#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OmniUIDocument-Swift.h>

@interface OUIRestoreSampleDocumentListController ()

@property (nonatomic, strong) NSURL *sampleDocumentsURL;

@end

@implementation OUIRestoreSampleDocumentListController

- (instancetype)initWithSampleDocumentsURL:(NSURL *)sampleDocumentsURL;
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.sampleDocumentsURL = sampleDocumentsURL;
        self.shouldShowLastModifiedDate = NO;
    }
    return self;
}

- (void)cancel:(id)sender;
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (NSString *)localizedNameForFileName:(NSString *)fileName;
{
    return [[OUIDocumentAppController controller] localizedNameForSampleDocumentNamed:fileName];
}

#pragma mark - UIViewController

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    UIBarButtonItem *cancel = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    self.navigationItem.leftBarButtonItem = cancel;
    
    // Load sample documents.
    OBASSERT([self.sampleDocumentsURL isFileURL]);
    
    __autoreleasing NSError *error = nil;
    
    NSArray *propertyKeys = @[NSURLIsDirectoryKey, NSURLAttributeModificationDateKey, NSURLTotalFileSizeKey];
    NSArray *fileURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.sampleDocumentsURL includingPropertiesForKeys:propertyKeys options:0 error:&error];
    if (!fileURLs) {
        OUI_PRESENT_ERROR_FROM(error, self);
        return;
    }
    
    // Filter
    NSArray *filteredFileURLs = fileURLs;
    if (self.fileFilterPredicate) {
        filteredFileURLs = [fileURLs filteredArrayUsingPredicate:self.fileFilterPredicate];
    }
    
    NSArray *sampleFileInfos = [filteredFileURLs arrayByPerformingBlock:^id(NSURL *fileURL) {
        BOOL isDirectory;
        if (!OFGetBoolResourceValue(fileURL, NSURLIsDirectoryKey, &isDirectory, NULL))
            OBASSERT_NOT_REACHED("Should be able to read our samples");
        __autoreleasing NSDate *modificationDate = nil;
        if (![fileURL getResourceValue:&modificationDate forKey:NSURLAttributeModificationDateKey error:NULL])
            OBASSERT_NOT_REACHED("Should be able to read our samples");
        __autoreleasing NSNumber *fileSize;
        if (![fileURL getResourceValue:&fileSize forKey:NSURLTotalFileSizeKey error:NULL])
            OBASSERT_NOT_REACHED("Should be able to read our samples");
        
        NSString *sampleName = fileURL.lastPathComponent;
        return [[ODAVFileInfo alloc] initWithOriginalURL:fileURL name:sampleName exists:YES directory:isDirectory size:[fileSize unsignedLongLongValue] lastModifiedDate:modificationDate];
    }];
    
    sampleFileInfos = [sampleFileInfos sortedArrayUsingComparator:^(ODAVFileInfo *fileInfo1, ODAVFileInfo *fileInfo2) {
        NSString *fileInfo1LocalizedName = [self localizedNameForFileName:[fileInfo1.name stringByDeletingPathExtension]];
        if (!fileInfo1LocalizedName)
            fileInfo1LocalizedName = [fileInfo1.name stringByDeletingPathExtension];
        
        NSString *fileInfo2LocalizedName = [self localizedNameForFileName:[fileInfo2.name stringByDeletingPathExtension]];
        if (!fileInfo2LocalizedName)
            fileInfo2LocalizedName = [fileInfo2.name stringByDeletingPathExtension];
        
        return [fileInfo1LocalizedName compare:fileInfo2LocalizedName];
    }];
    
    self.files = sampleFileInfos;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    ODAVFileInfo *fileInfo = self.files[indexPath.row];
    OUIDocumentSceneDelegate *sceneDelegate = self.sceneDelegate;
    NSURL *originalURL = fileInfo.originalURL;
    NSString *localizedName = [self localizedNameForFileName:fileInfo.name.stringByDeletingPathExtension];
    NSURL *targetURL = [sceneDelegate urlForNewDocumentInFolderAtURL:nil baseName:localizedName extension:originalURL.pathExtension];
    NSError *copyError = nil;
    if (![NSFileManager.defaultManager copyItemAtURL:originalURL toURL:targetURL error:&copyError]) {
        OUI_PRESENT_ERROR_FROM(copyError, self);
        return;
    }
    [self dismissViewControllerAnimated:YES completion:^{
        [sceneDelegate revealURLInDocumentBrowser:targetURL completion:NULL];
    }];
}

@end
