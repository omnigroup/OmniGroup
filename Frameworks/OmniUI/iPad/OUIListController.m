// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIListController.h"

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniFileStore/OFSFileInfo.h>

RCS_ID("$Id$");

@implementation OUIListController

@synthesize files = _files;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [super initWithNibName:@"OUIListController" bundle:OMNI_BUNDLE];
}

- (void)dealloc {
    [_files release];
    
    [super dealloc];
}

- (void)setFiles:(NSArray *)newFiles;
{
    [_files release];
    _files = [newFiles retain];
    
    [(UITableView *)self.view reloadData];
}

#pragma mark -
#pragma mark Private
- (BOOL)_canOpenFile:(OFSFileInfo *)fileInfo;
{
    return [[OUIAppController controller] canViewFileTypeWithIdentifier:[fileInfo UTI]];
}

#pragma mark -
#pragma mark Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    return [_files count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier] autorelease];
    }
    
    OFSFileInfo *fileInfo = [_files objectAtIndex:indexPath.row];
    cell.textLabel.text = [[fileInfo name] stringByDeletingPathExtension];
    cell.accessoryType = (![self _canOpenFile:fileInfo] && [fileInfo isDirectory]) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    
    BOOL canOpenFile = ([fileInfo isDirectory] || [self _canOpenFile:fileInfo]) && [fileInfo exists];
    cell.textLabel.textColor = canOpenFile ? [UIColor blackColor] : [UIColor grayColor];
    
    if (![fileInfo isDirectory] || [self _canOpenFile:fileInfo]) {
        NSDate *lastModifiedDate = [fileInfo lastModifiedDate];
        if (lastModifiedDate) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateStyle:NSDateFormatterMediumStyle];
            [formatter setLocale:[NSLocale currentLocale]];
            cell.detailTextLabel.text = [formatter stringFromDate:lastModifiedDate];
            [formatter release];
        }
    }
    else {
        cell.detailTextLabel.text = nil;
    }
    
    UIImage *icon = nil;
    if ([self _canOpenFile:fileInfo]) {
        OUIDocumentPicker *picker = [[OUIAppController controller] documentPicker];
        icon = [picker iconForUTI:[fileInfo UTI]];
    } else if ([fileInfo isDirectory]) {
        icon = [UIImage imageNamed:@"OUIFolder.png"];
    } else {
        icon = [UIImage imageNamed:@"OUIDocument.png"];
    }
    
    cell.imageView.image = icon;
    
    return cell;
}


#pragma mark -
#pragma mark Table view delegate
// TODO: All UITableViewDelegate Implementations should be performed in the subclass.

#pragma mark -
#pragma mark UIViewController
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation;
{
    return YES;
}

@end
