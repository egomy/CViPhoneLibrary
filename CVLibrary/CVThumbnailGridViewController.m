//
//  ThumbnailViewController.m
//  ColoringBook
//
//  Created by Kerem Karatal on 1/22/09.
//  Copyright 2009 Coding Ventures. All rights reserved.
//

#import "CVThumbnailGridViewController.h"

@interface CVThumbnailGridViewController()
- (void) commonInit;
@end

@implementation CVThumbnailGridViewController
@synthesize thumbnailView = thumbnailView_;

- (void) dealloc {
    [thumbnailView_ release];
    [super dealloc];
}

- (id) initWithCoder:(NSCoder *) coder {
	if (self = [super initWithCoder:coder]) {
        [self commonInit];
	}
	return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        [self commonInit];
    }
    return self;
}

- (void) commonInit {
    firstTimeDisplay_ = YES;
}

// Implement loadView to create a view hierarchy programmatically, without using a nib.
- (void)loadView {
    [super loadView];
    
	thumbnailView_ = [[CVThumbnailGridView alloc] initWithFrame:[[self view] bounds]];
	[thumbnailView_ setDataSource:self];	
	[thumbnailView_ setDelegate:self];
	[thumbnailView_ setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
	[[self view] addSubview:thumbnailView_];
    [thumbnailView_ reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
	if (firstTimeDisplay_) {
		[self.view setAlpha:0];
		[UIView beginAnimations:@"Test" context:nil];
		[UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
		[UIView setAnimationDuration:0.8];
		[self.view setAlpha:1.0];
		[UIView commitAnimations];
		firstTimeDisplay_ = NO;
	}
	[super viewWillAppear:animated];
}

- (void) viewDidAppear:(BOOL) animated {
    [super viewDidAppear:animated];
    [self.thumbnailView flashScrollIndicators];    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning]; // Releases the view if it doesn't have a superview
    // Release anything that's not essential, such as cached data
	
}

#pragma mark CVThumbnailGridViewDelegate methods

- (CVThumbnailGridViewCell *)thumbnailView:(CVThumbnailGridView *)thumbnailView cellAtIndexPath:(NSIndexPath *)indexPath {
    return nil;
}

- (NSInteger) numberOfCellsForThumbnailView:(CVThumbnailGridView *)thumbnailView {
    return 0;
}

@end
