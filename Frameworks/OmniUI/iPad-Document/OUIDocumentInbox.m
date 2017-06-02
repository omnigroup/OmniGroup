// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentInbox.h"

#import <MobileCoreServices/MobileCoreServices.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSLocalDirectoryScope.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSUtilities.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIErrors.h>
#import <OmniUnzip/OUUnzipArchive.h>
#import <OmniUnzip/OUUnzipEntry.h>


@implementation OUIDocumentInbox

RCS_ID("$Id$");

+ (void)_inAsyncFileAccessCloneInboxItem:(NSURL *)itemToMoveURL toScope:(ODSScope *)scope completionHandler:(void (^)(ODSFileItem *, NSError *))finishedBlock;
{
    // This deals with read-only files given to us in the Inbox on iOS. <bug:///60499> (OmniGraphSketcher needs to handle read-only files)
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        __autoreleasing NSError *attributesError = nil;
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:[[itemToMoveURL absoluteURL] path] error:&attributesError];
        if (!attributes) {
            // Hopefully non-fatal, but worrisome. We'll log it at least....
            NSLog(@"Error getting attributes of \"%@\": %@", [itemToMoveURL absoluteString], [attributesError toPropertyList]);
        } else {
            NSUInteger mode = [attributes filePosixPermissions];
            if ((mode & S_IWUSR) == 0) {
                mode |= S_IWUSR;
                attributesError = nil;
                if (![fileManager setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:mode] forKey:NSFilePosixPermissions] ofItemAtPath:[[itemToMoveURL absoluteURL] path] error:&attributesError]) {
                    NSLog(@"Error setting attributes of \"%@\": %@", [itemToMoveURL absoluteString], [attributesError toPropertyList]);
                }
            }
        }
    }
    
    BOOL shouldConvert = NO;
    OUIDocumentPicker *docPicker = [OUIDocumentAppController controller].documentPicker;
    OBASSERT(docPicker);
    if (docPicker && [docPicker.delegate respondsToSelector:@selector(documentPickerShouldOpenButNotDisplayUTType:)] && [docPicker.delegate respondsToSelector:@selector(documentPicker:saveNewFileIfAppropriateFromFile:completionHandler:)]) {
        BOOL isDirectory = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:[itemToMoveURL path] isDirectory:&isDirectory];
        shouldConvert = [docPicker.delegate documentPickerShouldOpenButNotDisplayUTType:OFUTIForFileExtensionPreferringNative([itemToMoveURL pathExtension], @(isDirectory))];
        
        if (shouldConvert) { // convert files we claim to view, but do not display in our doc-picker?
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [docPicker.delegate documentPicker:docPicker saveNewFileIfAppropriateFromFile:itemToMoveURL completionHandler:^(BOOL success, ODSFileItem *savedItem, ODSScope *currentScope) {
                    [docPicker.documentStore moveItems:[NSSet setWithObject:savedItem] fromScope:currentScope toScope:scope inFolder:scope.rootFolder completionHandler:^(NSSet *movedFileItems, NSArray *errorsOrNil) {
                        finishedBlock([movedFileItems anyObject], [errorsOrNil firstObject]);
                    }];
                }];
            }];
            return;
        }
    }
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [scope addDocumentInFolder:scope.rootFolder fromURL:itemToMoveURL option:ODSStoreAddByCopyingSourceToAvailableDestinationURL completionHandler:finishedBlock];
    }];
}

+ (void)cloneInboxItem:(NSURL *)inboxURL toScope:(ODSScope *)scope completionHandler:(void (^)(ODSFileItem *newFileItem, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(scope.hasFinishedInitialScan);
    
    completionHandler = [completionHandler copy];
    
    void (^finishedBlock)(ODSFileItem *newFileItem, NSError *errorOrNil) = ^(ODSFileItem *newFileItem, NSError *errorOrNil) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            
            if (completionHandler) {
                completionHandler(newFileItem, errorOrNil);
            }
        }];
    };
    
    finishedBlock = [finishedBlock copy];
    
    [scope performAsynchronousFileAccessUsingBlock:^{
        __autoreleasing NSError *error = nil;
        NSString *uti = OFUTIForFileURLPreferringNative(inboxURL, &error);
        if (!uti) {
            finishedBlock(nil, error);
            return;
        }
        
        NSInteger filesOpened = 0;
        BOOL isZip = ODSIsZipFileType(uti);
        OUUnzipArchive *archive = nil;
        if (isZip) {
            archive = [[OUUnzipArchive alloc] initWithPath:[inboxURL path] error:&error];
            if (!archive) {
                finishedBlock(nil, error);
                return;
            }
            
            NSMutableArray *unzippedURLs = [NSMutableArray array];
            for (NSString *name in [self topLevelEntryNamesInArchive:archive]) {
                BOOL isDirectory = [name hasSuffix:@"/"];
                NSString *fileName = [[name pathComponents] firstObject];
                NSString *unzippedUTI = OFUTIForFileExtensionPreferringNative([fileName pathExtension], [NSNumber numberWithBool:isDirectory]);
                
                if ([scope.documentStore canViewFileTypeWithIdentifier:unzippedUTI]) {
                    NSURL *unzippedFileURL = [archive URLByWritingTemporaryCopyOfTopLevelEntryNamed:fileName error:&error];
                    if (!unzippedFileURL)
                        continue;
                    [unzippedURLs addObject:unzippedFileURL];
                }
            }
            for (NSURL *unzippedFileURL in unzippedURLs) {
                [self _inAsyncFileAccessCloneInboxItem:unzippedFileURL toScope:scope completionHandler:finishedBlock];
                filesOpened += 1;
            }
        } else {
            if ([scope.documentStore canViewFileTypeWithIdentifier:uti]) {
                [self _inAsyncFileAccessCloneInboxItem:inboxURL toScope:scope completionHandler:finishedBlock];
                filesOpened += 1;
            }
        }
        
        if (filesOpened == 0) {
            // we're not going to delete the file in the inbox here, because another document store may want to lay claim to this inbox item. Give them a chance to. The calls to cleanupInboxItem: should be daisy-chained from OUIDocumentAppController or it's subclass.
            
            NSLog(@"Delegate says it cannot view file type \"%@\"", uti);
            
            NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
            OBASSERT(![NSString isEmptyString:appName]);
            
            __autoreleasing NSError *utiShouldNotBeIncludedError = nil;
            NSString *title =  NSLocalizedStringFromTableInBundle(@"Unable to open file.", @"OmniUIDocument", OMNI_BUNDLE, @"error title");
            NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ cannot open this type of file.", @"OmniUIDocument", OMNI_BUNDLE, @"error description"), appName];
            OUIDocumentError(&utiShouldNotBeIncludedError, OUICannotMoveItemFromInbox, title, description);
            
            finishedBlock(nil, utiShouldNotBeIncludedError);
            return;
        }
    }];
}

+ (BOOL)coordinatedRemoveItemAtURL:(NSURL *)URL error:(NSError **)outError;
{
    __block BOOL success = NO;
    __block NSError *deleteError = nil;
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    
    [coordinator coordinateWritingItemAtURL:URL options:NSFileCoordinatorWritingForDeleting error:outError byAccessor:^(NSURL *newURL) {
        __autoreleasing NSError *error = nil;
        if (![[NSFileManager defaultManager] removeItemAtURL:newURL error:&error]) {
            // Deletion of item at URL failed
            NSLog(@"Deletion of inbox item failed: %@", [error toPropertyList]);
            deleteError = error; // strong-ify
            return;
        }
        
        success = YES;
    }];
    
    if (!success && outError)
        *outError = deleteError;
    
    return success;
}

#pragma mark - Private

+ (NSArray *)topLevelEntryNamesInArchive:(OUUnzipArchive *)archive;
{
    NSMutableArray *result = [NSMutableArray array];
    for (OUUnzipEntry *entry in archive.entries) {
        if ([entry.name rangeOfString:@"__MACOSX" options:(NSAnchoredSearch | NSCaseInsensitiveSearch)].location != NSNotFound)
            continue;
        NSRange slashRange = [entry.name rangeOfString:@"/"];
        if (slashRange.location == NSNotFound || slashRange.location == (entry.name.length - 1))
            [result addObject:entry.name];
    }
    return result;
}

@end
