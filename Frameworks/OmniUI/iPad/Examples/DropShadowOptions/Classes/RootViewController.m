//
//  RootViewController.m
//  DropShadowOptions
//
//  Created by Timothy J. Wood on 4/2/10.
//  Copyright The Omni Group 2010. All rights reserved.
//

#import "RootViewController.h"
#import "DetailViewController.h"

#import "PlainCGShadowDemo.h"
#import "RedrawnCGShadowDemo.h"
#import "LayerShadowDemo.h"
#import "RasterizedLayerShadowDemo.h"
#import "OmniUIShadowDemo.h"

@implementation RootViewController

- (void)dealloc {
    [detailViewController release];
    [super dealloc];
}

@synthesize detailViewController;


#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidUnload;
{
    [_demos release];
    _demos = nil;
    
    [super viewDidUnload];
}


- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.clearsSelectionOnViewWillAppear = NO;
    self.contentSizeForViewInPopover = CGSizeMake(320.0, 600.0);
    
    NSMutableArray *demos = [NSMutableArray array];
    
    [demos addObject:[[[PlainCGShadowDemo alloc] init] autorelease]]; // Draw shadow with CG, inside the view's backing store, scaling it on size changes
    [demos addObject:[[[RedrawnCGShadowDemo alloc] init] autorelease]]; // Draw shadow with CG, inside the view's backing store, redrawing it on size changes
    [demos addObject:[[[LayerShadowDemo alloc] init] autorelease]]; // Content inside the view's backing store, shadow provided by CA
    [demos addObject:[[[RasterizedLayerShadowDemo alloc] init] autorelease]]; // Content inside the view's backing store, shadow provided by CA but rasterization cached
    [demos addObject:[[[OmniUIShadowDemo alloc] init] autorelease]]; // Image-stretching views
    
    _demos = [[NSArray alloc] initWithArray:demos];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    return YES;
}

#pragma mark -
#pragma mark UITableViewDataSource

enum {
    AnimationTypeSection,
    DriverTypeSection,
    DemoSection,
    SectionCount
};

- (NSInteger)numberOfSectionsInTableView:(UITableView *)aTableView;
{
    return SectionCount;
}


- (NSInteger)tableView:(UITableView *)aTableView numberOfRowsInSection:(NSInteger)section;
{
    switch (section) {
        case AnimationTypeSection:
            return AnimationTypeCount;
        case DriverTypeSection:
            return 2;
        case DemoSection:
        default:
            return [_demos count];
    }
}


- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
    switch (section) {
        case AnimationTypeSection:
            return @"Animation Type";
        case DriverTypeSection:
            return @"Animation Driver";
        case DemoSection:
        default:
            return @"Shadow Option";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    switch (indexPath.section) {
        case AnimationTypeSection: {
            NSString *title = indexPath.row == 0 ? @"Resize" : @"Slide";
            
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:title];
            if (cell == nil) {
                cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:title] autorelease];
                cell.textLabel.text = title;
            }
            cell.accessoryType = (detailViewController.animationType == indexPath.row) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            return cell;
        }
    
        case DriverTypeSection: {
            NSString *title = indexPath.row == 0 ? @"One-time change" : @"User interaction";
            
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:title];
            if (cell == nil) {
                cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:title] autorelease];
                cell.textLabel.text = title;
            }
            cell.accessoryType = (detailViewController.useTimer == (indexPath.row == 1)) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            return cell;
        }
    
        case DemoSection:
        default: {
            ShadowDemo *demo = [_demos objectAtIndex:indexPath.row];
            
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:demo.name];
            if (cell == nil) {
                cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:demo.name] autorelease];
                cell.textLabel.text = demo.name;
            }
            cell.accessoryType = (detailViewController.demo == demo) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            return cell;
        }
    }
}

#pragma mark -
#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)aTableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    switch (indexPath.section) {
        case AnimationTypeSection:
            detailViewController.animationType = indexPath.row;
            break;
        case DriverTypeSection:
            detailViewController.useTimer = (indexPath.row == 1);
            break;
        case DemoSection:
        default: {
            ShadowDemo *demo = [_demos objectAtIndex:indexPath.row];
            detailViewController.demo = demo;
            break;
        }
    }
    
    [aTableView reloadData];
}

@end

