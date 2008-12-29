//
//  SampleAppAppDelegate.m
//  SampleApp
//
//  Created by Timothy J. Wood on 10/4/08.
//  Copyright The Omni Group 2008. All rights reserved.
//

#import "SampleAppAppDelegate.h"
#import "RootViewController.h"


@implementation SampleAppAppDelegate

@synthesize window;
@synthesize navigationController;


- (void)applicationDidFinishLaunching:(UIApplication *)application {
	
	// Configure and show the window
	[window addSubview:[navigationController view]];
	[window makeKeyAndVisible];
}


- (void)applicationWillTerminate:(UIApplication *)application {
	// Save data if appropriate
}


- (void)dealloc {
	[navigationController release];
	[window release];
	[super dealloc];
}

@end
