#import "NativeModuleEx.h"
#import <React/RCTLog.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <React/RCTConvert.h>
#import <opencv2/opencv.hpp>

@implementation NativeModuleEx

RCT_EXPORT_MODULE();

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

RCT_EXPORT_METHOD(detectRectangle:(NSString *)imageAsBase64 callback:(RCTResponseSenderBlock)callback) {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @autoreleasepool {
      @try {
        CIImage* inputImage = [self decodeBase64ToImage:imageAsBase64];
        
        // need to convert the CI image to a CG image before use, otherwise there can be some unexpected behaviour on some devices
        CIContext *context = [CIContext contextWithOptions:nil];
        CGImageRef cgDetectionImage = [context createCGImage:inputImage fromRect:inputImage.extent];
        CIImage *detectionImage = [CIImage imageWithCGImage:cgDetectionImage];
//        CGRect imageBounds = detectionImage.extent;
        detectionImage = [detectionImage imageByApplyingOrientation:kCGImagePropertyOrientationUp];

        CIRectangleFeature *_borderDetectLastRectangleFeature = [self biggestRectangleInRectangles:[[self highAccuracyRectangleDetector] featuresInImage:detectionImage] image:detectionImage];
        
        if (_borderDetectLastRectangleFeature) {
          NSDictionary *rectangleCoordinates = [self computeRectangle:_borderDetectLastRectangleFeature forImage: detectionImage];
          callback(@[[NSNull null], @{
                       @"detectedRectangle": rectangleCoordinates,
          }]);
        } else {
          callback(@[[NSNull null], @{
                       @"detectedRectangle": @FALSE,
          }]);
        }
        
        CGImageRelease(cgDetectionImage);
      }
      @catch (NSException * e) {
        NSLog(@"Failed to parse image: %@", e);
        callback(@[[NSNull null], @{
                     @"detectedRectangle": @FALSE,
        }]);
      }
    }
  });
}


RCT_EXPORT_METHOD(cropAndPerspectiveTransformCorrection:(NSString *)imageAsBase64 points:(NSDictionary *)points callback:(RCTResponseSenderBlock)callback) {
//  UIImage* _sourceImage = [self decodeBase64ToUIImage:imageAsBase64];
  CIImage* _sourceImage = [self decodeBase64ToImage:imageAsBase64];

  CIContext *context = [CIContext contextWithOptions:nil];
  CGImageRef cgDetectionImage = [context createCGImage:_sourceImage fromRect:_sourceImage.extent];
  CIImage *detectionImage = [CIImage imageWithCGImage:cgDetectionImage];
  detectionImage = [detectionImage imageByApplyingOrientation:kCGImagePropertyOrientationUp];
  
  CIContext *context2 = [CIContext contextWithOptions:nil];
  CGImageRef cgimage = [context2 createCGImage:detectionImage fromRect:[detectionImage extent]];
  UIImage *image = [UIImage imageWithCGImage:cgimage scale: 1.0 orientation:UIImageOrientationRight];
  CGImageRelease(cgimage);
//  _sourceImage = [self scaleAndRotateImage:_sourceImage];
  cv::Mat originalRot = [self cvMatFromUIImage:image];
  cv::Mat original;
  cv::transpose(originalRot, original);
  CGImageRelease(cgDetectionImage);
  originalRot.release();
  
  cv::flip(original, original, 1);
  
  float xScale = 1;
  float yScale = 1;
  CGPoint ptTopLeft = CGPointMake([points[@"topLeft"][@"x"] floatValue] * xScale, [points[@"topLeft"][@"y"] floatValue] * yScale);
  CGPoint ptTopRight = CGPointMake([points[@"topRight"][@"x"] floatValue] * xScale, [points[@"topRight"][@"y"] floatValue] * yScale);
  CGPoint ptBottomLeft = CGPointMake([points[@"bottomLeft"][@"x"] floatValue] * xScale, [points[@"bottomLeft"][@"y"] floatValue] * yScale);
  CGPoint ptBottomRight = CGPointMake([points[@"bottomRight"][@"x"] floatValue] * xScale, [points[@"bottomRight"][@"y"] floatValue] * yScale);
  
  CGFloat w1 = sqrt( pow(ptBottomRight.x - ptBottomLeft.x , 2) + pow(ptBottomRight.x - ptBottomLeft.x, 2));
  CGFloat w2 = sqrt( pow(ptTopRight.x - ptTopLeft.x , 2) + pow(ptTopRight.x - ptTopLeft.x, 2));
  
  CGFloat h1 = sqrt( pow(ptTopRight.y - ptBottomRight.y , 2) + pow(ptTopRight.y - ptBottomRight.y, 2));
  CGFloat h2 = sqrt( pow(ptTopLeft.y - ptBottomLeft.y , 2) + pow(ptTopLeft.y - ptBottomLeft.y, 2));
  
  CGFloat maxWidth = (w1 < w2) ? w1 : w2;
  CGFloat maxHeight = (h1 < h2) ? h1 : h2;
  
  cv::Point2f src[4], dst[4];
  src[0].x = ptTopLeft.x;
  src[0].y = ptTopLeft.y;
  src[1].x = ptTopRight.x;
  src[1].y = ptTopRight.y;
  src[2].x = ptBottomRight.x;
  src[2].y = ptBottomRight.y;
  src[3].x = ptBottomLeft.x;
  src[3].y = ptBottomLeft.y;
  
  dst[0].x = 0;
  dst[0].y = 0;
  dst[1].x = maxWidth - 1;
  dst[1].y = 0;
  dst[2].x = maxWidth - 1;
  dst[2].y = maxHeight - 1;
  dst[3].x = 0;
  dst[3].y = maxHeight - 1;
  
  cv::Mat undistorted = cv::Mat( cvSize(maxWidth,maxHeight), CV_8UC1);
  cv::warpPerspective(original, undistorted, cv::getPerspectiveTransform(src, dst), cvSize(maxWidth, maxHeight));
  
  UIImage *newImage = [self UIImageFromCVMat:undistorted];
  NSData *imageToEncode = UIImageJPEGRepresentation(newImage, 1.0);
  callback(@[[NSNull null], @{@"newImage": [imageToEncode base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength]}]);
  
  undistorted.release();
  original.release();
  
  //  CIImage *capturedImage = [self decodeBase64ToImage:imageAsBase64];
  //  CIContext *contextMain = [CIContext contextWithOptions:nil];
  //  CGImageRef cgDetectionImage = [contextMain createCGImage:capturedImage fromRect:capturedImage.extent];
  //  CIImage *detectionImage = [CIImage imageWithCGImage:cgDetectionImage];
  //  detectionImage = [detectionImage imageByApplyingOrientation:kCGImagePropertyOrientationLeft];
  ////  CGRect imageBounds = detectionImage.extent;
  //
  //
  //  float xScale = 1;
  //  float yScale = 1;
  //
  //  NSMutableDictionary *rectangleCoordinates = [NSMutableDictionary new];
  //
  //  CGPoint newLeft = CGPointMake([points[@"topLeft"][@"x"] floatValue] * xScale, [points[@"topLeft"][@"y"] floatValue] * yScale);
  //  CGPoint newRight = CGPointMake([points[@"topRight"][@"x"] floatValue] * xScale, [points[@"topRight"][@"y"] floatValue] * yScale);
  //  CGPoint newBottomLeft = CGPointMake([points[@"bottomLeft"][@"x"] floatValue] * xScale, [points[@"bottomLeft"][@"y"] floatValue] * yScale);
  //  CGPoint newBottomRight = CGPointMake([points[@"bottomRight"][@"x"] floatValue] * xScale, [points[@"bottomRight"][@"y"] floatValue] * yScale);
  //
  //  rectangleCoordinates[@"inputTopLeft"] = [CIVector vectorWithCGPoint:newLeft];
  //  rectangleCoordinates[@"inputTopRight"] = [CIVector vectorWithCGPoint:newRight];
  //  rectangleCoordinates[@"inputBottomLeft"] = [CIVector vectorWithCGPoint:newBottomLeft];
  //  rectangleCoordinates[@"inputBottomRight"] = [CIVector vectorWithCGPoint:newBottomRight];
  //
  //  CIImage *correctPerspectiveForImage = [detectionImage imageByApplyingFilter:@"CIPerspectiveCorrection" withInputParameters:rectangleCoordinates];
  //
//    CIContext *context = [CIContext contextWithOptions:nil];
//    CGImageRef cgimage = [context createCGImage:correctPerspectiveForImage fromRect:[correctPerspectiveForImage extent]];
//    UIImage *image = [UIImage imageWithCGImage:cgimage scale: 1.0 orientation:UIImageOrientationRight];
  //
  //
  //  NSData *imageToEncode = UIImageJPEGRepresentation(image, 1.0);
  //  callback(@[[NSNull null], @{@"newImage": [imageToEncode base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength]}]);
  //
  //  CGImageRelease(cgDetectionImage);
  //  CGImageRelease(cgimage);
}

- (CIImage *)decodeBase64ToImage:(NSString *)strEncodeData {
  NSData *data = [[NSData alloc]initWithBase64EncodedString:strEncodeData options:NSDataBase64DecodingIgnoreUnknownCharacters];
  return [CIImage imageWithData:data];
}

- (UIImage *)decodeBase64ToUIImage:(NSString *)strEncodeData {
  NSData *data = [[NSData alloc]initWithBase64EncodedString:strEncodeData options:NSDataBase64DecodingIgnoreUnknownCharacters];
  return [UIImage imageWithData:data];
}

- (NSString *)encodeToBase64String:(UIImage *)image {
  NSData *imgData =UIImageJPEGRepresentation(image, 1);
  return [imgData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
}


- (UIImage *)scaleAndRotateImage:(UIImage *)image {
    int kMaxResolution = 2000; // Or whatever
    CGFloat scale = 1.0;
    if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]) {
        scale = [[UIScreen  mainScreen] scale];
        kMaxResolution *= scale;
    }
    
    CGImageRef imgRef = image.CGImage;
    
    CGFloat width = CGImageGetWidth(imgRef);
    CGFloat height = CGImageGetHeight(imgRef);
    
    
    CGAffineTransform transform = CGAffineTransformIdentity;
    CGRect bounds = CGRectMake(0, 0, width, height);
    if (width > kMaxResolution || height > kMaxResolution) {
        CGFloat ratio = width/height;
        if (ratio > 1) {
            bounds.size.width = kMaxResolution;
            bounds.size.height = roundf(bounds.size.width / ratio);
        }
        else {
            bounds.size.height = kMaxResolution;
            bounds.size.width = roundf(bounds.size.height * ratio);
        }
    }
    
    CGFloat scaleRatio = bounds.size.width / width;
    CGSize imageSize = CGSizeMake(CGImageGetWidth(imgRef), CGImageGetHeight(imgRef));
    CGFloat boundHeight;
    UIImageOrientation orient = image.imageOrientation;
    switch(orient) {
            
        case UIImageOrientationUp: //EXIF = 1
            transform = CGAffineTransformIdentity;
            break;
            
        case UIImageOrientationUpMirrored: //EXIF = 2
            transform = CGAffineTransformMakeTranslation(imageSize.width, 0.0);
            transform = CGAffineTransformScale(transform, -1.0, 1.0);
            break;
            
        case UIImageOrientationDown: //EXIF = 3
            transform = CGAffineTransformMakeTranslation(imageSize.width, imageSize.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationDownMirrored: //EXIF = 4
            transform = CGAffineTransformMakeTranslation(0.0, imageSize.height);
            transform = CGAffineTransformScale(transform, 1.0, -1.0);
            break;
            
        case UIImageOrientationLeftMirrored: //EXIF = 5
            boundHeight = bounds.size.height;
            bounds.size.height = bounds.size.width;
            bounds.size.width = boundHeight;
            transform = CGAffineTransformMakeTranslation(imageSize.height, imageSize.width);
            transform = CGAffineTransformScale(transform, -1.0, 1.0);
            transform = CGAffineTransformRotate(transform, 3.0 * M_PI / 2.0);
            break;
            
        case UIImageOrientationLeft: //EXIF = 6
            boundHeight = bounds.size.height;
            bounds.size.height = bounds.size.width;
            bounds.size.width = boundHeight;
            transform = CGAffineTransformMakeTranslation(0.0, imageSize.width);
            transform = CGAffineTransformRotate(transform, 3.0 * M_PI / 2.0);
            break;
            
        case UIImageOrientationRightMirrored: //EXIF = 7
            boundHeight = bounds.size.height;
            bounds.size.height = bounds.size.width;
            bounds.size.width = boundHeight;
            transform = CGAffineTransformMakeScale(-1.0, 1.0);
            transform = CGAffineTransformRotate(transform, M_PI / 2.0);
            break;
            
        case UIImageOrientationRight: //EXIF = 8
            boundHeight = bounds.size.height;
            bounds.size.height = bounds.size.width;
            bounds.size.width = boundHeight;
            transform = CGAffineTransformMakeTranslation(imageSize.height, 0.0);
            transform = CGAffineTransformRotate(transform, M_PI / 2.0);
            break;
            
        default:
            [NSException raise:NSInternalInconsistencyException format:@"Invalid image orientation"];
            
    }
    
    UIGraphicsBeginImageContext(bounds.size);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    if (orient == UIImageOrientationRight || orient == UIImageOrientationLeft) {
        CGContextScaleCTM(context, -scaleRatio, scaleRatio);
        CGContextTranslateCTM(context, -height, 0);
    }
    else {
        CGContextScaleCTM(context, scaleRatio, -scaleRatio);
        CGContextTranslateCTM(context, 0, -height);
    }
    
    CGContextConcatCTM(context, transform);
    
    CGContextDrawImage(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, width, height), imgRef);
    UIImage *imageCopy = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return imageCopy;
}

- (UIImage *)UIImageFromCVMat:(cv::Mat)cvMat
{
    NSData *data = [NSData dataWithBytes:cvMat.data length:cvMat.elemSize() * cvMat.total()];

    CGColorSpaceRef colorSpace;

    if (cvMat.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }

    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);

    CGImageRef imageRef = CGImageCreate(cvMat.cols,                                     // Width
                                        cvMat.rows,                                     // Height
                                        8,                                              // Bits per component
                                        8 * cvMat.elemSize(),                           // Bits per pixel
                                        cvMat.step[0],                                  // Bytes per row
                                        colorSpace,                                     // Colorspace
                                        kCGImageAlphaNone | kCGBitmapByteOrderDefault,  // Bitmap info flags
                                        provider,                                       // CGDataProviderRef
                                        NULL,                                           // Decode
                                        false,                                          // Should interpolate
                                        kCGRenderingIntentDefault);                     // Intent

    UIImage *image = [[UIImage alloc] initWithCGImage:imageRef scale: 1.0 orientation:UIImageOrientationUp];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);

    return image;
}

- (cv::Mat)cvMatFromUIImage:(UIImage *)image
{
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.height;
    CGFloat rows = image.size.width;

    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels

    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to backing data
                                                    cols,                       // Width of bitmap
                                                    rows,                       // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags

    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);

    return cvMat;
}


/*!
 Gets a rectangle detector that can be used to plug an image into and find the rectangles from
 */
- (CIDetector *)highAccuracyRectangleDetector
{
  static CIDetector *detector = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^
                {
    detector = [CIDetector detectorOfType:CIDetectorTypeRectangle context:nil options:@{CIDetectorAccuracy : CIDetectorAccuracyHigh, CIDetectorReturnSubFeatures: @(YES) }];
  });
  return detector;
}

/*!
 Finds the best fitting rectangle from the list of rectangles found in the image
 */
- (CIRectangleFeature *)biggestRectangleInRectangles:(NSArray *)rectangles image:(CIImage *)image
{
  if (![rectangles count]) return nil;
  
  float halfPerimiterValue = 0;
  
  CIRectangleFeature *biggestRectangle = [rectangles firstObject];
  
  for (CIRectangleFeature *rect in rectangles) {
    CGPoint p1 = rect.topLeft;
    CGPoint p2 = rect.topRight;
    CGFloat width = hypotf(p1.x - p2.x, p1.y - p2.y);
    
    CGPoint p3 = rect.topLeft;
    CGPoint p4 = rect.bottomLeft;
    CGFloat height = hypotf(p3.x - p4.x, p3.y - p4.y);
    
    CGFloat currentHalfPerimiterValue = height + width;
    
    if (halfPerimiterValue < currentHalfPerimiterValue) {
      halfPerimiterValue = currentHalfPerimiterValue;
      biggestRectangle = rect;
    }
  }
  
  return biggestRectangle;
}

/*!
 Maps the coordinates to the correct orientation.  This maybe can be cleaned up and removed if the orientation is set on the input image.
 */
- (NSDictionary *) computeRectangle: (CIRectangleFeature *) rectangle forImage: (CIImage *) image {
  CGRect imageBounds = image.extent;
  
  if (!rectangle) return nil;
  return @{
    @"bottomLeft": @{
        @"y": @(rectangle.bottomLeft.x),
        @"x": @(rectangle.bottomLeft.y)
    },
    @"bottomRight": @{
        @"y": @(rectangle.bottomRight.x),
        @"x": @(rectangle.bottomRight.y)
    },
    @"topLeft": @{
        @"y": @(rectangle.topLeft.x),
        @"x": @(rectangle.topLeft.y)
    },
    @"topRight": @{
        @"y": @(rectangle.topRight.x),
        @"x": @(rectangle.topRight.y)
    },
    @"dimensions": @{@"height": @(imageBounds.size.width), @"width": @(imageBounds.size.height)}
  };
}



@end
