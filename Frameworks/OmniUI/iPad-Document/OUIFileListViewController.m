// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIFileListViewController.h"

#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniFileStore/OFSFileInfo.h>

RCS_ID("$Id$");

@implementation OUIFileListViewController
{
    NSArray *_files;
}


@synthesize files = _files;
- (void)setFiles:(NSArray *)newFiles;
{
    _files = newFiles;
    
    [(UITableView *)self.view reloadData];
}

// for subclasses
- (NSString *)localizedNameForFileName:(NSString *)fileName;
{
    return fileName;
}

#pragma mark -
#pragma mark Private

- (BOOL)_canOpenFile:(OFSFileInfo *)fileInfo;
{
    return [[OUIDocumentAppController controller] canViewFileTypeWithIdentifier:[fileInfo UTI]];
}

#pragma mark -
#pragma mark UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    return [_files count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    
    OFSFileInfo *fileInfo = [_files objectAtIndex:indexPath.row];
    BOOL isDocument = [self _canOpenFile:fileInfo];
    BOOL isFolder = !isDocument && fileInfo.isDirectory; // Things that we can open might be directories, but we won't let the user navigate into them.s
    
    if (isDocument) {
        // Look up localized sample document names and trim path extensions
        NSString *localizedFileName = [self localizedNameForFileName:[[fileInfo name] stringByDeletingPathExtension]];
        if (!localizedFileName)
            localizedFileName = [fileInfo name];
        
        cell.textLabel.text = localizedFileName;
    } else {
        // Leave the folder name exactly the way the user had it.
        cell.textLabel.text = [fileInfo name];
    }
    
    cell.accessoryType = isFolder ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    
    BOOL canOpenFile = (isFolder || isDocument) && [fileInfo exists];
    cell.textLabel.textColor = canOpenFile ? [UIColor blackColor] : [UIColor grayColor];
    
    if (isDocument) {
        NSDate *lastModifiedDate = [fileInfo lastModifiedDate];
        if (lastModifiedDate) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateStyle:NSDateFormatterMediumStyle];
            [formatter setLocale:[NSLocale currentLocale]];
            cell.detailTextLabel.text = [formatter stringFromDate:lastModifiedDate];
        }
    }
    else {
        cell.detailTextLabel.text = nil;
    }
    
    UIImage *icon = nil;
    if (isDocument) {
        OUIDocumentPicker *picker = [[OUIDocumentAppController controller] documentPicker];
        icon = [picker iconForUTI:[fileInfo UTI]];
    } else if (isFolder) {
        icon = [UIImage imageNamed:@"OUIFolder.png"];
    } else {
        icon = [UIImage imageNamed:@"OUIDocument.png"];
    }
    
    cell.imageView.image = icon;
    
    return cell;
}

#pragma mark - UIViewController

- (BOOL)shouldAutorotate;
{
    return YES;
}

@end
