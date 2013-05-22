// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISyncDownloader.h"

#import <OmniUI/OUIAppController.h>
#import <OmniUnzip/OUUnzipArchive.h>
#import <OmniUnzip/OUUnzipEntry.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniAppKit/NSFileWrapper-OAExtensions.h>
#import <OmniUIDocument/OUIDocumentPicker.h>

#import <MobileCoreServices/MobileCoreServices.h>

RCS_ID("$Id$");

NSString * const OUISyncDownloadFinishedNotification = @"OUISyncDownloadFinishedNotification";
NSString * const OUISyncDownloadURL = @"OUISyncDownloadURL";
NSString * const OUISyncDownloadCanceledNotification = @"OUISyncDownloadCanceledNotification";

@implementation OUISyncDownloader

@synthesize progressView = _progressView;
@synthesize cancelButton = _cancelButton;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [super initWithNibName:@"OUISyncDownloader" bundle:OMNI_BUNDLE];
}


#pragma mark - API

- (NSString *)unarchiveFileAtPath:(NSString *)filePathWithArchiveExtension error:(NSError **)outError;
{
    NSString *unarchivedFolder = [filePathWithArchiveExtension stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    OUUnzipArchive *archive = [[OUUnzipArchive alloc] initWithPath:filePathWithArchiveExtension error:outError];
    if (!archive)
        return nil;
    
    NSString *unarchivedFilePath = nil;
    for (OUUnzipEntry *entry in [archive entries]) {
        if ([[entry name] hasPrefix:@"__MACOSX/"])
            continue; // Skip over any __MACOSX metadata (resource forks, etc.)
        
        NSArray *subEntries = [archive entriesWithNamePrefix:[entry name]];
        if ([subEntries count] > 1)
            continue;
        
        
        __autoreleasing NSError *error;
        BOOL didWrite = NO;
        @autoreleasepool {
            NSData *uncompressed = [archive dataForEntry:entry error:&error];
            
            if (uncompressed) {
                NSArray *pathComponents = [[entry name] pathComponents];
                if (pathComponents && [pathComponents count]) {
                    NSString *base = [pathComponents objectAtIndex:0];
                    if (!unarchivedFilePath)
                        unarchivedFilePath = [unarchivedFolder stringByAppendingPathComponent:base];
                    
                    // not currently able to handle a zip file with more than one flat or one package file, so will end up returning the first entry unzipped
                    OBASSERT([[unarchivedFolder stringByAppendingPathComponent:base] isEqualToString:unarchivedFilePath]);
                }
                
                NSString *entryPath = [unarchivedFolder stringByAppendingPathComponent:[entry name]];
                if ([fileManager createPathToFile:entryPath attributes:nil error:&error])
                    didWrite = [uncompressed writeToFile:entryPath options:0 error:&error];
            }
        }
        
        if (!didWrite) {
            OBASSERT(error);
            if (outError)
                *outError = error;
            break;
        }
    }
    
    return unarchivedFilePath;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.progressView.progress = 0;
    
    UIImage *backgroundImage = [[UIImage imageNamed:@"OUIExportCancelBadge.png"] stretchableImageWithLeftCapWidth:6 topCapHeight:0];
    [self.cancelButton setBackgroundImage:backgroundImage forState:UIControlStateNormal];
    [self.cancelButton setTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUIDocument", OMNI_BUNDLE, @"button title") forState:UIControlStateNormal];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    self.progressView.progress = 0;
}

- (void)uploadData:(NSData *)data toURL:(NSURL *)targetURL;
{
    [self uploadFileWrapper:[NSFileWrapper fileWrapperWithFilename:nil contents:data] toURL:targetURL];
}

@end
