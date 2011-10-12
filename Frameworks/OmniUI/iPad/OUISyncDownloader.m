// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISyncDownloader.h"

#import <OmniUI/OUIAppController.h>
#import <OmniUnzip/OUUnzipArchive.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniAppKit/NSFileWrapper-OAExtensions.h>
#import <OmniUI/OUIDocumentPicker.h>

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

- (void)dealloc;
{
    [_progressView release], _progressView = nil;
    [_cancelButton release], _cancelButton = nil;
    
    [super dealloc];
}

#pragma mark -
#pragma mark API

- (void)download:(OFSFileInfo *)aFile;
{
    // Should be overridden in subclass.
}
- (IBAction)cancelDownload:(id)sender;
{
    // Should be overridden in subclass.
}

- (void)uploadFileWrapper:(NSFileWrapper *)fileWrapper toURL:(NSURL *)targetURL;
{
    // Should be overridden in subclass.
}

- (NSString *)unarchiveFileAtPath:(NSString *)filePathWithArchiveExtension error:(NSError **)error;
{
    NSString *unarchivedFolder = [filePathWithArchiveExtension stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    OUUnzipArchive *archive = [[[OUUnzipArchive alloc] initWithPath:filePathWithArchiveExtension error:error] autorelease];
    if (!archive)
        return nil;
    
    NSString *unarchivedFilePath = nil;
    for (OUUnzipEntry *entry in [archive entries]) {
        if ([[entry name] hasPrefix:@"__MACOSX/"])
            continue; // Skip over any __MACOSX metadata (resource forks, etc.)
        
        NSArray *subEntries = [archive entriesWithNamePrefix:[entry name]];
        if ([subEntries count] > 1)
            continue;
        
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        BOOL didWrite = NO;
        NSData *uncompressed = [archive dataForEntry:entry error:error];
        
        if (uncompressed) {
            NSArray *pathComponents = [[entry name] pathComponents];
            if (pathComponents && [pathComponents count]) {
                NSString *base = [pathComponents objectAtIndex:0];
                if (!unarchivedFilePath)
                    unarchivedFilePath = [[unarchivedFolder stringByAppendingPathComponent:base] retain];
                
                // not currently able to handle a zip file with more than one flat or one package file, so will end up returning the first entry unzipped
                OBASSERT([[unarchivedFolder stringByAppendingPathComponent:base] isEqualToString:unarchivedFilePath]);
            }
            
            NSString *entryPath = [unarchivedFolder stringByAppendingPathComponent:[entry name]];
            if ([fileManager createPathToFile:entryPath attributes:nil error:error])
                didWrite = [uncompressed writeToFile:entryPath options:0 error:error];
        }
        
        if (!didWrite)
            [*error retain];
        
        [pool release];
        
        if (!didWrite) {
            OBASSERT(error);
            [*error autorelease];
            break;
        }
    }
    
    return [unarchivedFilePath autorelease];
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.progressView.progress = 0;
    
    UIImage *backgroundImage = [[UIImage imageNamed:@"OUIExportCancelBadge.png"] stretchableImageWithLeftCapWidth:6 topCapHeight:0];
    [self.cancelButton setBackgroundImage:backgroundImage forState:UIControlStateNormal];
    [self.cancelButton setTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title") forState:UIControlStateNormal];
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
