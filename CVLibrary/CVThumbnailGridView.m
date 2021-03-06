//
//  ThumbnailView.m
//  ColoringBook
//
//  Created by Kerem Karatal on 1/22/09.
//  Copyright 2009 Coding Ventures. All rights reserved.
//

#include "CGUtils.h"

#import "CVThumbnailGridView.h"
#import "UIImage+Adornments.h"

@interface CVThumbnailGridView()
- (void) commonInit;
- (void) animateThumbnailViewCell:(CVThumbnailGridViewCell *) cell;
- (CGSize) recalculateThumbnailCellSize;
- (NSUInteger) calculateNumOfColumns;
- (CGRect) rectForColumn:(NSUInteger) column row:(NSUInteger) row;
- (CGFloat) columnSpacing;
- (CVThumbnailGridViewCell *) createCellFromDataSourceForIndexPath:(NSIndexPath *) indexPath;
- (NSString *) keyFromIndexPath:(NSIndexPath *) indexPath;
- (void) cleanupNonVisibleCells;
- (void) removeCell:(CVThumbnailGridViewCell *) cell;
- (void) maybeAutoscrollForThumb:(CVThumbnailGridViewCell *) cell;
- (CGFloat) autoscrollDistanceForProximityToEdge:(CGFloat)proximity;
- (void) legalizeAutoscrollDistance;
- (void) autoscrollTimerFired:(NSTimer*)timer;
- (void) moveCellsStartingIndex:(NSUInteger) startIndex
                    endingIndex:(NSUInteger) endIndex
                  withIncrement:(NSInteger) increment
                  excludingCell:(CVThumbnailGridViewCell *) excludedCell;
- (CGRect) thumbnailAreaBounds;
- (CGFloat) headerHeight;
- (CGFloat) footerHeight;
- (NSInteger) startingRowOnPage;
- (NSInteger) endingRowOnPage;
@end 

@implementation CVThumbnailGridView
@synthesize dataSource = dataSource_;
@synthesize delegate = delegate_;
@synthesize numOfRows = numOfRows_;
@synthesize numOfColumns = numOfColumns_;
@synthesize leftMargin = leftMargin_;
@synthesize rightMargin = rightMargin_;
@synthesize topMargin = topMargin_;
@synthesize bottomMargin = bottomMargin_;
@synthesize rowSpacing = rowSpacing_;
@synthesize thumbnailCount = thumbnailCount_;
@synthesize cellStyle = cellStyle_;
@synthesize fitNumberOfColumnsToFullWidth = fitNumberOfColumnsToFullWidth_;
@synthesize animateSelection = animateSelection_;
@synthesize editing = editing_;
@synthesize imageLoadingIcon = imageLoadingIcon_;
@synthesize deleteSignIcon = deleteSignIcon_;
@synthesize deleteSignBackgroundColor = deleteSignBackgroundColor_;
@synthesize deleteSignForegroundColor = deleteSignForegroundColor_;
@synthesize deleteSignSideLength = deleteSignSideLength_;
@synthesize headerView = headerView_;
@synthesize footerView = footerView_;

- (void)dealloc {
    [cellStyle_ release];
    [reusableThumbnails_ release];
    [thumbnailsInUse_ release];
    [adornedImageLoadingIcon_ release];
    [imageLoadingIcon_ release];
    [deleteSignIcon_ release];
    [deleteSignForegroundColor_ release];
    [deleteSignBackgroundColor_ release];
    [headerView_ release];
    [footerView_ release];
    [super dealloc];
}

#pragma mark Initializers and properties

#define LEFT_MARGIN_DEFAULT 5.0
#define RIGHT_MARGIN_DEFAULT 5.0
#define TOP_MARGIN_DEFAULT 0.0 // TODO: Top margin is always half of ROW_SPACING 
#define ROW_SPACING_DEFAULT 10.0
#define COLUMN_COUNT_DEFAULT 1
#define DELETE_SIGN_SIDE_LENGTH_DEFAULT 34.0

- (id) initWithCoder:(NSCoder *) coder {
	if (self = [super initWithCoder:coder]) {
		[self commonInit];
	}
	return self;
}

- (id) initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        // Initialization code
		[self commonInit];
    }
    return self;
}

- (void) commonInit {
    leftMargin_ = LEFT_MARGIN_DEFAULT;
    rightMargin_ = RIGHT_MARGIN_DEFAULT;
    topMargin_ = TOP_MARGIN_DEFAULT;
    rowSpacing_ = ROW_SPACING_DEFAULT;
    numOfColumns_ = COLUMN_COUNT_DEFAULT;
    isAnimated_ = NO;
    animateSelection_ = YES;
    fitNumberOfColumnsToFullWidth_ = NO;
    editing_ = NO;
    
    cellStyle_ = [[CVStyle alloc] init];     
    thumbnailsInUse_ = [[NSMutableDictionary alloc] init];
    reusableThumbnails_ = [[NSMutableSet alloc] init];
    firstVisibleRow_ = NSIntegerMax;
    lastVisibleRow_ = NSIntegerMin;
    self.backgroundColor = [UIColor clearColor];
    deleteSignSideLength_ = DELETE_SIGN_SIDE_LENGTH_DEFAULT;
    self.deleteSignBackgroundColor = [UIColor blackColor];
    self.deleteSignForegroundColor = [UIColor redColor];
    headerView_ = nil;
    footerView_ = nil;
    [self setDelaysContentTouches:YES];
    [self setCanCancelContentTouches:NO];
}

- (void) setCellStyle:(CVStyle *) style {
    if (cellStyle_ != style) {
        [cellStyle_ release];
        cellStyle_ = [style retain];
        thumbnailCellSize_ = [self recalculateThumbnailCellSize];
        [self setNeedsLayout];
    }
}

- (void) setNumOfColumns:(NSInteger) numOfColumns {    
    // If numOfColumns == 0, set it to 1, 0 is not expected.
    numOfColumns_ = (numOfColumns == 0) ? 1 : numOfColumns;
}


- (NSUInteger) calculateNumOfColumns {
    NSUInteger numOfColumns;
    CGRect visibleBounds = [self bounds];
    numOfColumns = floorf((visibleBounds.size.width - leftMargin_ - rightMargin_)/thumbnailCellSize_.width);
    numOfColumns = (numOfColumns == 0) ? 1 : numOfColumns;
    return numOfColumns;
}

#define THUMBNAIL_LEFT_MARGIN 17.0
#define THUMBNAIL_TOP_MARGIN 17.0

- (CGSize) recalculateThumbnailCellSize {
    CGSize cellSize = [cellStyle_ sizeAfterStylingImage];

    // Add the margin data
    CGFloat deltaX = (THUMBNAIL_LEFT_MARGIN >= abs(cellStyle_.shadowStyle.offset.width)) ? THUMBNAIL_LEFT_MARGIN - abs(cellStyle_.shadowStyle.offset.width) : 0;
    CGFloat deltaY = (THUMBNAIL_TOP_MARGIN >= abs(cellStyle_.shadowStyle.offset.height)) ? THUMBNAIL_TOP_MARGIN - abs(cellStyle_.shadowStyle.offset.height) : 0;
    
    cellSize.width += deltaX;
    cellSize.height += deltaY;
    return cellSize;
}

- (void) reloadData {
    thumbnailCount_ = [dataSource_ numberOfCellsForThumbnailView:self];
    
    for (CVThumbnailGridViewCell *thumbnailViewCell in [self subviews]) {
        if ([thumbnailViewCell isKindOfClass:[CVThumbnailGridViewCell class]]) {
            [reusableThumbnails_ addObject:thumbnailViewCell];
            [thumbnailViewCell removeFromSuperview];
        }
    }
    
    // no rows or columns are now visible; note this by making the firsts very high and the lasts very low
    firstVisibleRow_ = NSIntegerMax;
    lastVisibleRow_  = NSIntegerMin;

    [self setNeedsLayout];
}

#pragma mark Layout 

- (void) setLeftMargin:(CGFloat) leftMargin {
    leftMargin_ = leftMargin;
    if (fitNumberOfColumnsToFullWidth_) {
        numOfColumns_ = [self calculateNumOfColumns];
    }
}

- (void) setRightMargin:(CGFloat) rightMargin {
    rightMargin_ = rightMargin;
    if (fitNumberOfColumnsToFullWidth_) {
        numOfColumns_ = [self calculateNumOfColumns];
    }
}

- (CGRect) thumbnailAreaBounds {
    CGFloat newY = (nil != headerView_) ? self.bounds.origin.y + headerView_.frame.size.height : self.bounds.origin.y;
    CGFloat newHeight = (nil != footerView_) ? self.bounds.size.height - footerView_.frame.size.height : self.bounds.size.height;
    CGRect thumbnailAreaBounds = CGRectMake(self.bounds.origin.x, newY , self.bounds.size.width, newHeight);
    return thumbnailAreaBounds;
}

- (CGFloat) headerHeight {
    return (nil != headerView_) ? headerView_.frame.size.height : 0;
}

- (CGFloat) footerHeight {
    return (nil != footerView_) ? footerView_.frame.size.height : 0;
}

- (NSInteger) startingRowOnPage {
    CGFloat rowHeight = rowSpacing_ + thumbnailCellSize_.height;
    return MAX(0, floorf((self.contentOffset.y - [self headerHeight]) / rowHeight));
}

- (NSInteger) endingRowOnPage {
    CGFloat rowHeight = rowSpacing_ + thumbnailCellSize_.height;
    return MIN(numOfRows_ - 1, floorf(((CGRectGetMaxY([self bounds]) - [self headerHeight]) / rowHeight)));
}

- (CGRect) rectForColumn:(NSUInteger) column row:(NSUInteger) row {
    CGFloat xPos = leftMargin_ + (thumbnailCellSize_.width + [self columnSpacing]) * column;
    CGFloat yPos = (thumbnailCellSize_.height + rowSpacing_) * row + [self headerHeight];
    CGRect rect = CGRectMake(xPos, yPos, thumbnailCellSize_.width, thumbnailCellSize_.height);

    return rect;
}

- (CGFloat) columnSpacing {
    CGFloat columnSpacing = 0;
    if (numOfColumns_ > 1) {
        columnSpacing = MAX(0, (self.bounds.size.width - (thumbnailCellSize_.width * numOfColumns_) - leftMargin_ - rightMargin_) / (numOfColumns_ - 1));
    }
    
    return columnSpacing;
}

- (CVThumbnailGridViewCell *) dequeueReusableCellWithIdentifier:(NSString *) identifier {
    CVThumbnailGridViewCell *cell = [reusableThumbnails_ anyObject];
    
    if (cell) {
        [[cell retain] autorelease];
        [reusableThumbnails_ removeObject:cell];
    }
    return cell;
}

- (void) layoutSubviews {
    [super layoutSubviews];

    [headerView_ setFrame:CGRectMake(0.0, 0.0, headerView_.frame.size.width, headerView_.frame.size.height)];
    if (nil == [headerView_ superview]) {
        [self addSubview:headerView_];
    }
        
    // Refresh our thumbnail count    
    thumbnailCount_ = [dataSource_ numberOfCellsForThumbnailView:self];    
    thumbnailCellSize_ = [self recalculateThumbnailCellSize];

    if (fitNumberOfColumnsToFullWidth_) {
        numOfColumns_ = [self calculateNumOfColumns];
    }
    numOfRows_ = ceil( (CGFloat) thumbnailCount_ / numOfColumns_);

    if (isAnimated_ || numOfRows_ == 0)
        return;

    CGFloat height = topMargin_ + [self headerHeight] + [self footerHeight] + (thumbnailCellSize_.height + rowSpacing_) * numOfRows_;
    CGSize scrollViewSize = CGSizeMake(self.bounds.size.width, height);
    [self setContentSize:scrollViewSize];

    // Below algorithm is inspired/taken from Tiling Sample code in Apple iPhone SDK

    [self cleanupNonVisibleCells];
    
    NSInteger startingRowOnPage = [self startingRowOnPage];
    NSInteger endingRowOnPage = [self endingRowOnPage];
//    NSLog(@"Start: %d, End: %d", startingRowOnPage, endingRowOnPage);
    for (NSInteger row = startingRowOnPage; row <= endingRowOnPage; row++) {
        for (NSInteger column = 0; column < numOfColumns_; column++) {
            BOOL thumbnailMissing = (firstVisibleRow_ > row) || (lastVisibleRow_ < row);
            if (thumbnailMissing) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row column:column];
                NSInteger currentCellNo = row * numOfColumns_ + column;
                if (currentCellNo >= thumbnailCount_)
                    break;
                [self createCellFromDataSourceForIndexPath:indexPath];
            }
        }
    }

    firstVisibleRow_ = startingRowOnPage;
    lastVisibleRow_ = endingRowOnPage;

    [footerView_ setFrame:CGRectMake(0.0, height - footerView_.frame.size.height, footerView_.frame.size.width, footerView_.frame.size.height)];
    if (nil == [footerView_ superview]) {
        [self addSubview:footerView_];
    }

}

- (void) cleanupNonVisibleCells {
    for (CVThumbnailGridViewCell *thumbnail in [self subviews]) {
        if ([thumbnail isKindOfClass:[CVThumbnailGridViewCell class]]) { 
            CGRect thumbnailFrame = [self convertRect:[thumbnail frame] toView:self];

            // Take into account the rowSpacing_
            thumbnailFrame = CGRectMake(thumbnailFrame.origin.x, thumbnailFrame.origin.y, 
                                        thumbnailFrame.size.width, thumbnailFrame.size.height + rowSpacing_);
            
            if (!CGRectIntersectsRect(thumbnailFrame, [self bounds])) {
                [self removeCell:thumbnail];
//                NSLog(@"%@ removed, Bounds:(%f, %f) (%f, %f)", [[thumbnail cachedImage] imageUrl], 
//                      self.bounds.origin.x, self.bounds.origin.y,  
//                      self.bounds.size.width, self.bounds.size.height);
            }
        }
    }
}

- (CVThumbnailGridViewCell *) cellForIndexPath:(NSIndexPath *) indexPath {
    CVThumbnailGridViewCell *cell = [thumbnailsInUse_ objectForKey:[self keyFromIndexPath:indexPath]];
    if (nil == cell) {
        [self cleanupNonVisibleCells];
        cell = [self createCellFromDataSourceForIndexPath:indexPath];
//        NSLog(@"New Cell %@", [[cell cachedImage] imageUrl]);
    }
    return cell;
}

- (CVThumbnailGridViewCell *) createCellFromDataSourceForIndexPath:(NSIndexPath *) indexPath {
    CVThumbnailGridViewCell *cell = [dataSource_ thumbnailView:self cellAtIndexPath:indexPath];
    if (nil != cell) {
        CGRect frame = [self rectForColumn:[indexPath column] row:[indexPath row]];       
        [cell setFrame:frame];
        [cell setHome:frame];
        [cell setUserInteractionEnabled:YES];
        [cell setDelegate:self];
        [cell setIndexPath:indexPath];
        [cell setEditing:editing_];
        [cell setUpperLeftMargin:CGPointMake(THUMBNAIL_LEFT_MARGIN, THUMBNAIL_TOP_MARGIN)];
        [cell setStyle:cellStyle_];
        [self addSubview:cell];
        [thumbnailsInUse_ setObject:cell forKey:[self keyFromIndexPath:indexPath]];
    } else {
        NSLog(@"Datasource returned nil thumbnail cell");
    }        
    
    return cell;
}

- (void) removeCell:(CVThumbnailGridViewCell *) cell {
    [reusableThumbnails_ addObject:cell];
    [cell removeFromSuperview];
    [thumbnailsInUse_ removeObjectForKey:[self keyFromIndexPath:[cell indexPath]]];
}

- (NSString *) keyFromIndexPath:(NSIndexPath *) indexPath {
    NSString *key = [NSString stringWithFormat:@"%d, %d", indexPath.row, indexPath.column];
    return key;
}

#pragma mark Editing 

- (void) setEditing:(BOOL) editing {
    editing_ = editing;
    for (CVThumbnailGridViewCell *cell in [thumbnailsInUse_ allValues]) {
        [cell setEditing:editing];
    }
}

- (void) insertCellsAtIndexPaths:(NSArray *) indexPaths {
    for (NSIndexPath *indexPath in indexPaths) {
        // Check if it is a visible area
        CGRect cellRect = [self rectForColumn:indexPath.column row:indexPath.row];
        if (CGRectIntersectsRect(cellRect, [self bounds])) {
            // Move the cells
            NSInteger endingRowOnPage = [self endingRowOnPage];
            
            NSUInteger startIndex = endingRowOnPage * numOfColumns_ + numOfColumns_;
            NSUInteger endIndex = [indexPath indexForNumOfColumns:numOfColumns_];
            if (startIndex >= thumbnailCount_) {
                startIndex = thumbnailCount_ - 1;
            }
            if (startIndex >= endIndex) {
                NSInteger increment = -1;
                [self moveCellsStartingIndex:startIndex
                                 endingIndex:endIndex withIncrement:increment excludingCell:nil];
            }
            
            // Insert the new cell            
            [self createCellFromDataSourceForIndexPath:indexPath];
        }
    }
}

- (void) deleteCellsAtIndexPaths:(NSArray *)indexPaths {
    for (NSIndexPath *indexPath in indexPaths) {
        [self removeCell:[self cellForIndexPath:indexPath]];

        NSInteger endingRowOnPage = [self endingRowOnPage];        
        NSUInteger startIndex = [indexPath indexForNumOfColumns:numOfColumns_] + 1;
        NSUInteger endIndex = endingRowOnPage * numOfColumns_ + numOfColumns_;
        if (endIndex >= thumbnailCount_) {
            endIndex = thumbnailCount_ - 1;
        }
        if (endIndex >= startIndex) {
            NSInteger increment = 1;
            [self moveCellsStartingIndex:startIndex
                             endingIndex:endIndex withIncrement:increment excludingCell:nil];
        }
    }
}

- (void) moveCellsStartingIndex:(NSUInteger) startIndex
                    endingIndex:(NSUInteger) endIndex
                  withIncrement:(NSInteger) increment
                  excludingCell:(CVThumbnailGridViewCell *) excludedCell {
    NSInteger i = startIndex;
    NSInteger row, column;
    NSInteger modifiedEndIndex = endIndex + increment;
    while (((i > modifiedEndIndex) && (increment == -1)) || ((i < modifiedEndIndex) && (increment == 1))) {
        row = floor(i / numOfColumns_);
        column = i - row * numOfColumns_;
        CVThumbnailGridViewCell *cell = [self cellForIndexPath:[NSIndexPath indexPathForRow:row column:column]];        
//        NSLog(@"Row - %d, Column - %d For index = %d, image = %@", row, column, i, [[cell cachedImage] imageUrl]);
        if (nil == cell) {
            NSLog(@"Cell is nil");
        }
        if (nil != cell && cell != excludedCell) {
            // Go opposite direction
            NSInteger moveToColumn = column - increment;
            NSInteger moveToRow = row;
            if (moveToColumn < 0) {
                moveToColumn = numOfColumns_ - 1;
                moveToRow = row - increment;
            } else if (moveToColumn == numOfColumns_) {
                moveToColumn = 0;
                moveToRow = row - increment;
            }
//            NSLog(@"Calculated -> Start (%d, %d) MoveTo (%d, %d)", row, column, moveToRow, moveToColumn);
            CGRect frame = [self rectForColumn:moveToColumn row:moveToRow];
            
            [cell setIndexPath:[NSIndexPath indexPathForRow:moveToRow column:moveToColumn]];
            [thumbnailsInUse_ setObject:cell forKey:[self keyFromIndexPath:[NSIndexPath indexPathForRow:moveToRow column:moveToColumn]]];
            
            [cell setHome:frame];
            [cell goHome];
        }
        i += increment;
    }
    if (i > 0) {
        [thumbnailsInUse_ removeObjectForKey:[self keyFromIndexPath:[NSIndexPath indexPathForRow:row column:column]]];
    }
}

#pragma mark CVThumbnailGridViewCellDelegate methods 

- (UIImage *) adornedImageLoadingIcon {
    if (nil == adornedImageLoadingIcon_) {
        if (nil != self.cellStyle) {
            adornedImageLoadingIcon_ = [[self.cellStyle imageByApplyingStyleToImage:self.imageLoadingIcon] retain];
        }
    }
    return adornedImageLoadingIcon_;
}

#define DELETE_SIGN_LINE_WIDTH 4.0
#define SCALE_FACTOR 0.75
#define BITS_PER_COMPONENT 8
#define NUM_OF_COMPONENTS 4

- (UIImage *) deleteSignIcon {
    if (nil == deleteSignIcon_) {
        // Assume always a square
        CGSize size = CGSizeMake(deleteSignSideLength_, deleteSignSideLength_);
        CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, size.width, size.height,
                                                     BITS_PER_COMPONENT,
                                                     NUM_OF_COMPONENTS * size.width, // We need to have RGBA with alpha
                                                     colorSpaceRef,
                                                     kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(colorSpaceRef);
        CGRect rect = CGRectMake(0.0, 0.0, size.width, size.height);
        CGContextSetFillColorWithColor(context, [[UIColor clearColor] CGColor]);
        CGContextFillRect(context, rect);
        CGContextBeginTransparencyLayer(context, NULL);
        
        // Draw the Circle
        CGContextSetFillColorWithColor(context, [self.deleteSignBackgroundColor CGColor]);
        CGContextSetStrokeColorWithColor(context, [self.deleteSignForegroundColor CGColor]);
        CGContextSetLineWidth(context, DELETE_SIGN_LINE_WIDTH);
        CGRect circleRect = CGRectMake(DELETE_SIGN_LINE_WIDTH / 2, DELETE_SIGN_LINE_WIDTH / 2, size.width - DELETE_SIGN_LINE_WIDTH , size.height - DELETE_SIGN_LINE_WIDTH);
        CGContextAddEllipseInRect(context, circleRect);
        CGContextDrawPath(context, kCGPathFillStroke);
        
        // Draw the X in the circle
        CGContextSetLineWidth(context, DELETE_SIGN_LINE_WIDTH);
        CGContextSetLineCap(context, kCGLineCapRound);
        CGFloat deleteSignCrossLength = ((size.width / 2) - DELETE_SIGN_LINE_WIDTH) * SCALE_FACTOR;
        CGFloat deleteSignCrossOffset = deleteSignCrossLength / sqrt(2);
        CGPoint centerPoint = CGPointMake(size.width / 2, size.height / 2);
        CGPoint startPoint = CGPointMake(centerPoint.x - deleteSignCrossOffset, centerPoint.y - deleteSignCrossOffset);
        CGPoint endPoint = CGPointMake(centerPoint.x + deleteSignCrossOffset, centerPoint.y + deleteSignCrossOffset);        
        CGContextMoveToPoint(context, startPoint.x, startPoint.y);
        CGContextAddLineToPoint(context, endPoint.x, endPoint.y);
        
        startPoint = CGPointMake(centerPoint.x + deleteSignCrossOffset, centerPoint.y - deleteSignCrossOffset);
        endPoint = CGPointMake(centerPoint.x - deleteSignCrossOffset, centerPoint.y + deleteSignCrossOffset);
        CGContextMoveToPoint(context, startPoint.x, startPoint.y);
        CGContextAddLineToPoint(context, endPoint.x, endPoint.y);
        CGContextDrawPath(context, kCGPathFillStroke);
        
        CGContextEndTransparencyLayer(context);

        CGImageRef cgImage = CGBitmapContextCreateImage(context);
        self.deleteSignIcon = [UIImage imageWithCGImage:cgImage];
        CGImageRelease(cgImage);
        CGContextRelease(context);
    }
    return deleteSignIcon_;
}

- (void) deleteSignWasTapped:(CVThumbnailGridViewCell *) cell {
    if ([dataSource_ respondsToSelector:@selector(thumbnailView:canEditCellAtIndexPath:)]) {
        if (![dataSource_ thumbnailView:self canEditCellAtIndexPath:cell.indexPath]) 
            return;
    }

    if ([dataSource_ respondsToSelector:@selector(thumbnailView:commitEditingStyle:forCellAtIndexPath:)]) {
        [dataSource_ thumbnailView:self commitEditingStyle:CVThumbnailGridViewCellEditingStyleDelete forCellAtIndexPath:cell.indexPath];
    }
}

- (void)thumbnailGridViewCellWasTapped:(CVThumbnailGridViewCell *) cell {
    if (animateSelection_) {
        [self animateThumbnailViewCell:cell];
    } else {
        if ([delegate_ respondsToSelector:@selector(thumbnailView:didSelectCellAtIndexPath:)]) {
            [delegate_ thumbnailView:self didSelectCellAtIndexPath:[cell indexPath]];
        }
    }
}

- (void)thumbnailGridViewCellStartedTracking:(CVThumbnailGridViewCell *) cell {
    [self bringSubviewToFront:cell];
}

- (void)thumbnailGridViewCellMoved:(CVThumbnailGridViewCell *) draggingThumb {
    [self maybeAutoscrollForThumb:draggingThumb];
    
    // Estimate cell number we are moving to based on location
    NSInteger draggingThumbMoveToColumn = floor((CGRectGetMidX([draggingThumb frame]) - leftMargin_) / (thumbnailCellSize_.width + [self columnSpacing]));
    NSInteger draggingThumbMoveToRow = floor((CGRectGetMidY([draggingThumb frame]) - [self headerHeight]) / (thumbnailCellSize_.height + rowSpacing_));
    NSInteger moveToIndex = draggingThumbMoveToRow * numOfColumns_ + draggingThumbMoveToColumn;
    
    if (draggingThumbMoveToColumn < 0 || draggingThumbMoveToColumn >= numOfColumns_) return;
    if (moveToIndex < 0 || moveToIndex >= thumbnailCount_) return;
    
    // Calculate starting cell number
    NSUInteger startingColumn = floor(([draggingThumb home].origin.x - leftMargin_) / (thumbnailCellSize_.width + [self columnSpacing]));
    NSUInteger startingRow = floor(([draggingThumb home].origin.y - [self headerHeight])/ (thumbnailCellSize_.height + rowSpacing_));
    NSUInteger startingIndex = startingRow * numOfColumns_ + startingColumn;

//    NSLog(@"Start %d, %d - %d  -- Move to: %d, %d - %d", startingRow, startingColumn, startingIndex, draggingThumbMoveToRow, draggingThumbMoveToColumn, moveToIndex);

    if (moveToIndex == startingIndex) return;
    
    BOOL moveToHigherIndex = moveToIndex > startingIndex;
    
    NSInteger endIndex = moveToIndex;
    NSInteger increment = moveToHigherIndex ? 1 : -1;
    
    [self moveCellsStartingIndex:startingIndex
                     endingIndex:endIndex
                   withIncrement:increment
                   excludingCell:draggingThumb];
    
    [draggingThumb setIndexPath:[NSIndexPath indexPathForRow:draggingThumbMoveToRow column:draggingThumbMoveToColumn]];
    [thumbnailsInUse_ setObject:draggingThumb forKey:[self keyFromIndexPath:[NSIndexPath indexPathForRow:draggingThumbMoveToRow column:draggingThumbMoveToColumn]]];
    CGRect moveToFrame = [self rectForColumn:draggingThumbMoveToColumn row:draggingThumbMoveToRow];
    [draggingThumb setHome:moveToFrame];
    if ([dataSource_ respondsToSelector:@selector(thumbnailView:moveCellAtIndexPath:toIndexPath:)]) {
        [dataSource_ thumbnailView:self 
               moveCellAtIndexPath:[NSIndexPath indexPathForRow:startingRow column:startingColumn] 
                       toIndexPath:[NSIndexPath indexPathForRow:draggingThumbMoveToRow column:draggingThumbMoveToColumn]];
    }
}

- (void)thumbnailGridViewCellStoppedTracking:(CVThumbnailGridViewCell *) cell {
    autoscrollDistance_ = 0;
    [autoscrollTimer_ invalidate];
    autoscrollTimer_ = nil;
}

#pragma mark AutoScroll 
// Autoscroll implementation below is taken from the Apple iPhone SDK sample code "ScrollViewSuite"

#define AUTOSCROLL_THRESHOLD 30
- (void) maybeAutoscrollForThumb:(CVThumbnailGridViewCell *) cell {
    autoscrollDistance_ = 0;
    
    if (CGRectIntersectsRect([cell frame], [self bounds])) {
        CGPoint touchLocation = [cell convertPoint:[cell touchLocation] toView:self];
        CGFloat distanceFromTopEdge  = touchLocation.y - CGRectGetMinY([self bounds]);
        CGFloat distanceFromBottomEdge = CGRectGetMaxY([self bounds]) - touchLocation.y;
        
        if (distanceFromTopEdge < AUTOSCROLL_THRESHOLD) {
            autoscrollDistance_ = [self autoscrollDistanceForProximityToEdge:distanceFromTopEdge] * -1;
        } else if (distanceFromBottomEdge < AUTOSCROLL_THRESHOLD) {
            autoscrollDistance_ = [self autoscrollDistanceForProximityToEdge:distanceFromBottomEdge];
        }        
    }
    
    if (autoscrollDistance_ == 0) {
        [autoscrollTimer_ invalidate];
        autoscrollTimer_ = nil;
    } 
    else if (autoscrollTimer_ == nil) {
        autoscrollTimer_ = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                                           target:self 
                                                         selector:@selector(autoscrollTimerFired:) 
                                                         userInfo:cell 
                                                          repeats:YES];
    } 
}

- (CGFloat) autoscrollDistanceForProximityToEdge:(CGFloat)proximity {
    return ceilf((AUTOSCROLL_THRESHOLD - proximity) / 5.0);
}

- (void) legalizeAutoscrollDistance {
    CGFloat minimumLegalDistance = [self contentOffset].y * -1;
    CGFloat maximumLegalDistance = [self contentSize].height - ([self frame].size.height + [self contentOffset].y);
    autoscrollDistance_ = MAX(autoscrollDistance_, minimumLegalDistance);
    autoscrollDistance_ = MIN(autoscrollDistance_, maximumLegalDistance);
}

- (void) autoscrollTimerFired:(NSTimer*)timer {
    [self legalizeAutoscrollDistance];
    
    CGPoint contentOffset = [self contentOffset];
    contentOffset.y += autoscrollDistance_;
    [self setContentOffset:contentOffset];
    
    CVThumbnailGridViewCell *cell = (CVThumbnailGridViewCell *)[timer userInfo];
    [cell moveByOffset:CGPointMake(0, autoscrollDistance_)];
}

#pragma mark Cell Selection Animation

#define SELECT_ANIMATION_DURATION 0.15
- (void) animateThumbnailViewCell:(CVThumbnailGridViewCell *) cell {
	//NSLog(@"*Animation 1 - x=%f, y=%f, width=%f, height=%f ", cell.frame.origin.x, cell.frame.origin.y, cell.frame.size.width, cell.frame.size.height);
	isAnimated_ = YES;
	[UIView beginAnimations:@"SelectThumbnail" context:cell];
	[UIView setAnimationDidStopSelector:@selector(animationFinished:finished:context:)];
	[UIView setAnimationDelegate:self];
	[UIView setAnimationDuration:SELECT_ANIMATION_DURATION];
	CGAffineTransform transform = CGAffineTransformMakeScale(1.2, 1.2);
	cell.transform = transform;
	[UIView commitAnimations];	
}

- (void) animationFinished:(NSString *)animationID finished:(BOOL)finished context:(void *)context {
	CVThumbnailGridViewCell *cell = (CVThumbnailGridViewCell *) context;
	if (animationID == @"SelectThumbnail") {
		//NSLog(@"**Animation 2 - x=%f, y=%f, width=%f, height=%f ", cell.frame.origin.x, cell.frame.origin.y, cell.frame.size.width, cell.frame.size.height);
		[UIView beginAnimations:@"DeSelectThumbnail" context:cell];
		[UIView setAnimationDidStopSelector:@selector(animationFinished:finished:context:)];
		[UIView setAnimationDelegate:self];
		[UIView setAnimationDuration:SELECT_ANIMATION_DURATION];
		CGAffineTransform transform = CGAffineTransformIdentity;
		cell.transform = transform;
		[UIView commitAnimations];			
	} else {
		//NSLog(@"***Animation 3 - x=%f, y=%f, width=%f, height=%f ", cell.frame.origin.x, cell.frame.origin.y, cell.frame.size.width, cell.frame.size.height);
        if ([delegate_ respondsToSelector:@selector(thumbnailView:didSelectCellAtIndexPath:)]) {
            [delegate_ thumbnailView:self didSelectCellAtIndexPath:[cell indexPath]];
        }

		isAnimated_ = NO;
	}	
}
@end

@implementation NSIndexPath(ThumbnailView) 

+ (NSIndexPath *) indexPathForIndex:(NSUInteger) index forNumOfColumns:(NSUInteger) numOfColumns {
    NSUInteger row = floor(index / numOfColumns);
    NSUInteger column = index - row * numOfColumns;
    
    return [NSIndexPath indexPathForRow:row column:column];
}
 
+ (NSIndexPath *) indexPathForRow:(NSUInteger)row column:(NSUInteger)column {
	return [NSIndexPath indexPathForRow:row inSection:column];
}

- (NSUInteger) column {
	return self.section;
}

- (NSUInteger) indexForNumOfColumns:(NSUInteger) numOfColumns {
    return self.row * numOfColumns + self.column;
}


@end
