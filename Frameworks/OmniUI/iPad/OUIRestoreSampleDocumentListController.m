// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIRestoreSampleDocumentListController.h"

#import <OmniUI/OUISingleDocumentAppController.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIDocumentStore.h>

#import <OmniFileStore/OFSFileManager.h>
#import <OmniFileStore/OFSFileInfo.h>

RCS_ID("$Id$");

@implementation OUIRestoreSampleDocumentListController

- (void)cancel:(id)sender;
{
    [self.navigationController dismissModalViewControllerAnimated:YES];
}

#pragma mark -
#pragma mark UIViewController

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Restore Sample Document", @"OmniUI", OMNI_BUNDLE, @"Restore Sample Document Title");
    
    UIBarButtonItem *cancel = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    self.navigationItem.leftBarButtonItem = cancel;
    [cancel release];
    
    // Load sample documents.
    NSURL *sampleDocumentsURL = [[OUISingleDocumentAppController controller] sampleDocumentsDirectoryURL];
    
    NSError *error = nil;
    OFSFileManager *fileManager = [[[OFSFileManager alloc] initWithBaseURL:sampleDocumentsURL error:&error] autorelease];
    if (error) {
        OUI_PRESENT_ERROR(error);
        return;
    }
    
    NSArray *sampleFiles = [fileManager directoryContentsAtURL:sampleDocumentsURL havingExtension:nil error:&error];
    if (error) {
        OUI_PRESENT_ERROR(error);
        return;
    }

    self.files = sampleFiles;
}

#pragma mark -
#pragma mark UITableViewDeletage
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    // Get Source Path
    NSURL *sampleDocumentsDirectoryURL = [[OUISingleDocumentAppController controller] sampleDocumentsDirectoryURL];
    OFSFileInfo *fileInfo = [self.files objectAtIndex:indexPath.row];
    BOOL isDirectory = [fileInfo isDirectory];
    NSString *fileName = [fileInfo name];
    NSURL *sampleDocumentURL = [sampleDocumentsDirectoryURL URLByAppendingPathComponent:fileName isDirectory:isDirectory];
    
    // Get Dest Path
    NSString *tempDirectory = NSTemporaryDirectory();
    NSString *tempPath = [tempDirectory stringByAppendingPathComponent:fileName];
    NSURL *tempURL = [NSURL fileURLWithPath:tempPath isDirectory:isDirectory];
    
    
    // Delete tempPath if it exists.
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:tempPath]) {
        if (![fileManager removeItemAtPath:tempPath error:&error]) {
            OUI_PRESENT_ERROR(error);
            return;
        }
    }
    
    // Should be able to copy sample doc to temp dir now.
    if (![fileManager copyItemAtURL:sampleDocumentURL toURL:tempURL error:&error]) {
        OUI_PRESENT_ERROR(error);
        return;
    }
    
    if (![fileManager setAttributes:[NSDictionary dictionaryWithObject:[NSDate date]
                                                           forKey:NSFileModificationDate] 
                       ofItemAtPath:tempPath 
                              error:&error]) {
        OUI_PRESENT_ERROR(error);
        return;
    }
    
    OUIAppController *appController = [OUIAppController controller];
    OUIDocumentPicker *documentPicker = appController.documentPicker;
    [documentPicker addDocumentFromURL:tempURL];
    
    [self dismissModalViewControllerAnimated:YES];
}

@end
