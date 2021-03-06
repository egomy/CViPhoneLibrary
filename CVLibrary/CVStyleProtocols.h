/*
 *  CVStyleProtocols.h
 *  CVLibrary
 *
 *  Created by Kerem Karatal on 8/10/09.
 *  Copyright 2009 Coding Ventures. All rights reserved.
 *
 */

@protocol CVRenderStyle
@required
// Image size is the requested resized image size 
- (void) drawInContext:(CGContextRef) context forImageSize:(CGSize) imageSize; 

- (CGSize) sizeAfterRenderingGivenInitialSize:(CGSize) size;
@end

