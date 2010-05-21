//
//  RootViewController.h
//  DropShadowOptions
//
//  Created by Timothy J. Wood on 4/2/10.
//  Copyright The Omni Group 2010. All rights reserved.
//

#import <UIKit/UIKit.h>

@class DetailViewController;

@interface RootViewController : UITableViewController {
    DetailViewController *detailViewController;
    NSArray *_demos;
}

@property (nonatomic, retain) IBOutlet DetailViewController *detailViewController;

@end
